import gdb


def stop_emulator(event):
    # A stopped guest must be killed before automatic detach could resume it.
    thread = gdb.selected_thread()
    if thread is not None and thread.is_stopped():
        with gdb.with_parameter('confirm', False):
            gdb.execute('kill')


gdb.events.gdb_exiting.connect(stop_emulator)
