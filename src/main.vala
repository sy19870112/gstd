/*
 * gstd/src/main.vala
 *
 * Main function for GStreamer daemon - framework for controlling audio and video streaming using D-Bus messages
 *
 * Copyright (c) 2010, RidgeRun
 * All rights reserved.
 *
 * GPL2 license - See http://www.opensource.org/licenses/gpl-2.0.php for complete text.
*/
using Gst;

/*Global Variable*/
public MainLoop loop = null;
public DBus.Connection conn = null;

private bool useSystemBus = false;
private bool useSessionBus = false;
private bool enableWatchdog = false;
private const GLib.OptionEntry[] options = {
  {"system", '\0', 0, OptionArg.NONE, ref useSystemBus, "Use system bus", null},
  {"session", '\0', 0, OptionArg.NONE, ref useSessionBus, "Use session bus", null},
  {"watchdog", 'w', 0, OptionArg.NONE, ref enableWatchdog, "Enable watchdog", null},
  {null}
};

public int main (string[] args)
{
  try {
    Posix.openlog("gstd", Posix.LOG_PID, Posix.LOG_USER /*Posix.LOG_DAEMON*/);
    Posix.syslog(Posix.LOG_ERR, "started");

    var opt = new GLib.OptionContext ("");
    opt.add_main_entries (options, null);

    try {
      opt.parse (ref args);
    }
    catch (GLib.OptionError e) {
      Posix.syslog(Posix.LOG_ERR, "OptionError failure: %s", e.message);
      return 1;
    }

    if (useSystemBus && useSessionBus) {
      Posix.syslog(Posix.LOG_ERR, "you have to choose: system or session bus");
      return 1;
    }

    /* Initializing GStreamer */
    Gst.init (ref args);

    /* Creating a GLib main loop with a default context */
    loop = new MainLoop (null, false);

    conn = DBus.Bus.get ((useSystemBus) ?
                           DBus.BusType.SYSTEM :
                           (useSessionBus) ?
                             DBus.BusType.SESSION :
                             DBus.BusType.STARTER);

    dynamic DBus.Object bus = conn.get_object ("org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus");

    /* Try to register service in session bus */
    uint request_name_result =
        bus.request_name ("com.ridgerun.gstreamer.gstd", (uint) 0);

    if (request_name_result != DBus.RequestNameReply.PRIMARY_OWNER) {
      Posix.syslog (Posix.LOG_ERR, "Failed to obtain primary ownership of " +
          "the service. This usually means there is another instance of " +
          "gstd already running");
      return 3;
    }

    /* Create our factory */
    var factory = new Factory ();

    conn.register_object ("/com/ridgerun/gstreamer/gstd/factory", factory);

    //monitor main loop with watchdog ?
    if (enableWatchdog) {
      Watchdog wd = new Watchdog(1000);
      factory.Alive.connect(() => {wd.Ping();});

      loop.run ();
    }
    else {
      loop.run ();
    }

    return 0;
  }
  catch (Error e) {
    Posix.syslog (Posix.LOG_ERR, "Error: %s", e.message);
    return 2;
  }
}


