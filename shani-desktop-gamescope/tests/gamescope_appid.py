# gamescope's GetAppIdFromReaper (src/Utils/Process.cpp), line for line: walk a
# pid's parents; at a process named "reaper", read "SteamLaunch" then "AppId=N"
# from its arguments (argv[1:] until "--"). Prints the app id found, or 0.
import sys
pid, found = int(sys.argv[1]), 0
while True:
    try:
        stat = open(f"/proc/{pid}/stat").read()
    except OSError:
        break
    name = stat[stat.index("(") + 1:stat.rindex(")")]
    parent = int(stat[stat.rindex(")") + 2:].split()[1])
    if name == "reaper":
        args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")[1:]
        launch = False
        for a in args:
            if a == b"SteamLaunch":
                launch = True
            elif a.startswith(b"AppId=") and a[6:].isdigit() and int(a[6:]) and launch:
                found = int(a[6:])
            elif a == b"--":
                break
    if parent in (-1, 0):
        break
    pid = parent
print(found)
