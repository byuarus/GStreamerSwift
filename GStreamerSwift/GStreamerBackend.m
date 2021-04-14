#import "GStreamerBackend.h"

#include <gst/gst.h>
#include <gst/video/video.h>

GST_DEBUG_CATEGORY_STATIC (debug_category);
#define GST_CAT_DEFAULT debug_category

/* Do not allow seeks to be performed closer than this distance. It is visually useless, and will probably
 * confuse some demuxers. */
#define SEEK_MIN_DELAY (500 * GST_MSECOND)

@interface GStreamerBackend()
-(void)setUIMessage:(gchar*) message;
-(void)app_function;
-(void)check_initialization_complete;
@end

@implementation GStreamerBackend {
    id ui_delegate;              /* Class that we use to interact with the user interface */
    GstElement *pipeline;        /* The running pipeline */
    GstElement *video_sink;      /* The video sink element which receives XOverlay commands */
    GMainContext *context;       /* GLib context used to run the main loop */
    GMainLoop *main_loop;        /* GLib main loop */
    gboolean initialized;        /* To avoid informing the UI multiple times about the initialization */
    UIView *ui_video_view;       /* UIView that holds the video */
    GstState state;              /* Current pipeline state */
    GstState target_state;       /* Desired pipeline state, to be set once buffering is complete */
    gint64 duration;             /* Cached clip duration */
    gint64 desired_position;     /* Position to seek to, once the pipeline is running */
    GstClockTime last_seek_time; /* For seeking overflow prevention (throttling) */
    gboolean is_live;            /* Live streams do not use buffering */
}

/*
 * Interface methods
 */

-(id) init:(id) uiDelegate videoView:(UIView *)video_view
{
    if (self = [super init])
    {
        self->ui_delegate = uiDelegate;
        self->ui_video_view = video_view;
        self->duration = GST_CLOCK_TIME_NONE;

        GST_DEBUG_CATEGORY_INIT (debug_category, "gstreamer_swift", 0, "GStreamer Swift");
        gst_debug_set_threshold_for_name("gstreamer_swift", GST_LEVEL_NONE); // Try GST_LEVEL_DEBUG

        /* Start the bus monitoring task */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self app_function];
        });
    }

    return self;
}

-(void) deinit
{
    if (main_loop) {
        g_main_loop_quit(main_loop);
    }
}

-(void) play
{
    target_state = GST_STATE_PLAYING;
    is_live = (gst_element_set_state (pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_NO_PREROLL);
}

-(void) pause
{
    target_state = GST_STATE_PAUSED;
    is_live = (gst_element_set_state (pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_NO_PREROLL);
}

-(void) setUri:(NSString*)uri
{
    const char *char_uri = [uri UTF8String];
    g_object_set(pipeline, "uri", char_uri, NULL);
    GST_DEBUG ("URI set to %s", char_uri);
}

/*
 * Private methods
 */

/* Change the message on the UI through the UI delegate */
-(void)setUIMessage:(gchar*) message
{
    NSString *string = [NSString stringWithUTF8String:message];
    if(ui_delegate && [ui_delegate respondsToSelector:@selector(gstreamerSetUIMessage:)])
    {
        [ui_delegate gstreamerSetUIMessage:string];
    }
}

/* Retrieve errors from the bus and show them on the UI */
static void error_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self)
{
    GError *err;
    gchar *debug_info;
    gchar *message_string;

    gst_message_parse_error (msg, &err, &debug_info);
    message_string = g_strdup_printf ("Error received from element %s: %s", GST_OBJECT_NAME (msg->src), err->message);
    g_clear_error (&err);
    g_free (debug_info);
    [self setUIMessage:message_string];
    g_free (message_string);
    gst_element_set_state (self->pipeline, GST_STATE_NULL);
}

/* Called when the End Of the Stream is reached. Just move to the beginning of the media and pause. */
static void eos_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self) {
    self->target_state = GST_STATE_PAUSED;
    self->is_live = (gst_element_set_state (self->pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_NO_PREROLL);
}

/* Called when buffering messages are received. We inform the UI about the current buffering level and
 * keep the pipeline paused until 100% buffering is reached. At that point, set the desired state. */
static void buffering_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self) {
    gint percent;

    if (self->is_live)
        return;

    gst_message_parse_buffering (msg, &percent);
    if (percent < 100 && self->target_state >= GST_STATE_PAUSED) {
        gchar * message_string = g_strdup_printf ("Buffering %d%%", percent);
        gst_element_set_state (self->pipeline, GST_STATE_PAUSED);
        [self setUIMessage:message_string];
        g_free (message_string);
    } else if (self->target_state >= GST_STATE_PLAYING) {
        gst_element_set_state (self->pipeline, GST_STATE_PLAYING);
    } else if (self->target_state >= GST_STATE_PAUSED) {
        [self setUIMessage:"Buffering complete"];
    }
}

/* Called when the clock is lost */
static void clock_lost_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self) {
    if (self->target_state >= GST_STATE_PLAYING) {
        gst_element_set_state (self->pipeline, GST_STATE_PAUSED);
        gst_element_set_state (self->pipeline, GST_STATE_PLAYING);
    }
}

/* Retrieve the video sink's Caps and tell the application about the media size */
static void check_media_size (GStreamerBackend *self) {
    GstElement *video_sink;
    GstPad *video_sink_pad;
    GstCaps *caps;
    GstVideoInfo info;

    /* Retrieve the Caps at the entrance of the video sink */
    g_object_get (self->pipeline, "video-sink", &video_sink, NULL);

    /* Do nothing if there is no video sink (this might be an audio-only clip */
    if (!video_sink) return;

    video_sink_pad = gst_element_get_static_pad (video_sink, "sink");
    caps = gst_pad_get_current_caps (video_sink_pad);

    if (gst_video_info_from_caps (&info, caps)) {
        info.width = info.width * info.par_n / info.par_d;
        GST_DEBUG ("Media size is %dx%d, notifying application", info.width, info.height);

        if (self->ui_delegate && [self->ui_delegate respondsToSelector:@selector(mediaSizeChanged:height:)])
        {
            [self->ui_delegate mediaSizeChanged:info.width height:info.height];
        }
    }

    gst_caps_unref(caps);
    gst_object_unref (video_sink_pad);
    gst_object_unref(video_sink);
}

/* Notify UI about pipeline state changes */
static void state_changed_cb (GstBus *bus, GstMessage *msg, GStreamerBackend *self)
{
    GstState old_state, new_state, pending_state;
    gst_message_parse_state_changed (msg, &old_state, &new_state, &pending_state);
    /* Only pay attention to messages coming from the pipeline, not its children */
    if (GST_MESSAGE_SRC (msg) == GST_OBJECT (self->pipeline)) {
        self->state = new_state;
        gchar *message = g_strdup_printf("State changed to %s", gst_element_state_get_name(new_state));
        [self setUIMessage:message];
        g_free (message);

        if (old_state == GST_STATE_READY && new_state == GST_STATE_PAUSED)
        {
            check_media_size(self);
        }
    }
}

/* Check if all conditions are met to report GStreamer as initialized.
 * These conditions will change depending on the application */
-(void) check_initialization_complete
{
    if (!initialized && main_loop) {
        GST_DEBUG ("Initialization complete, notifying application.");
        if (ui_delegate && [ui_delegate respondsToSelector:@selector(gstreamerInitialized)])
        {
            [ui_delegate gstreamerInitialized];
        }
        initialized = TRUE;
    }
}

/* Main method for the bus monitoring code */
-(void) app_function
{
    GstBus *bus;
    GSource *timeout_source;
    GSource *bus_source;
    GError *error = NULL;

    GST_DEBUG ("Creating pipeline");

    /* Create our own GLib Main Context and make it the default one */
    context = g_main_context_new ();
    g_main_context_push_thread_default(context);

    /* Build pipeline */
    pipeline = gst_parse_launch("playbin", &error);
    if (error) {
        gchar *message = g_strdup_printf("Unable to build pipeline: %s", error->message);
        g_clear_error (&error);
        [self setUIMessage:message];
        g_free (message);
        return;
    }

    /* Set the pipeline to READY, so it can already accept a window handle */
    gst_element_set_state(pipeline, GST_STATE_READY);

    video_sink = gst_bin_get_by_interface(GST_BIN(pipeline), GST_TYPE_VIDEO_OVERLAY);
    if (!video_sink) {
        GST_ERROR ("Could not retrieve video sink");
        return;
    }
    gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(video_sink), (guintptr) (id) ui_video_view);

    /* Instruct the bus to emit signals for each received message, and connect to the interesting signals */
    bus = gst_element_get_bus (pipeline);
    bus_source = gst_bus_create_watch (bus);
    g_source_set_callback (bus_source, (GSourceFunc) gst_bus_async_signal_func, NULL, NULL);
    g_source_attach (bus_source, context);
    g_source_unref (bus_source);
    g_signal_connect (G_OBJECT (bus), "message::error", (GCallback)error_cb, (__bridge void *)self);
    g_signal_connect (G_OBJECT (bus), "message::eos", (GCallback)eos_cb, (__bridge void *)self);
    g_signal_connect (G_OBJECT (bus), "message::state-changed", (GCallback)state_changed_cb, (__bridge void *)self);
    g_signal_connect (G_OBJECT (bus), "message::buffering", (GCallback)buffering_cb, (__bridge void *)self);
    g_signal_connect (G_OBJECT (bus), "message::clock-lost", (GCallback)clock_lost_cb, (__bridge void *)self);
    gst_object_unref (bus);

    /* Register a function that GLib will call 4 times per second */
    timeout_source = g_timeout_source_new (250);
    g_source_attach (timeout_source, context);
    g_source_unref (timeout_source);

    /* Create a GLib Main Loop and set it to run */
    GST_DEBUG ("Entering main loop...");
    main_loop = g_main_loop_new (context, FALSE);
    [self check_initialization_complete];
    g_main_loop_run (main_loop);
    GST_DEBUG ("Exited main loop");
    ui_delegate = NULL;
    ui_video_view = NULL;
    g_main_loop_unref (main_loop);
    main_loop = NULL;

    /* Free resources */
    g_main_context_pop_thread_default(context);
    g_main_context_unref (context);
    gst_element_set_state (pipeline, GST_STATE_NULL);
    gst_object_unref (pipeline);
    pipeline = NULL;

    return;
}

@end
