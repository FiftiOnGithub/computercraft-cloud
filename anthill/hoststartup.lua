peripheral.call("monitor_3", "setTextScale", 0.5)
peripheral.call("monitor_1", "setTextScale", 0.5)

multishell.launch(_ENV, "rom/programs/monitor.lua", "monitor_1", "anthill/host.lua")
multishell.launch(_ENV, "rom/programs/monitor.lua", "monitor_3", "anthill/tracker.lua")
multishell.launch(_ENV, "anthill/hostlog.lua")
