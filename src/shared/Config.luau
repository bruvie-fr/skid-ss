local Config = {}

Config.Version = "0.1.0"
Config.NetFolder = "SkidSS_Net"

Config.Limits = {
	MaxSteps = 200000,
	MaxLoopIterations = 100000,
	MaxWaitSeconds = 30,

	MaxLuaSteps = 10000000,
	MaxLuaSeconds = 2,
	MaxLuaDepth = 200,
}

Config.UI = {
	ToggleKey = Enum.KeyCode.RightShift,
	Accent = Color3.fromRGB(124, 92, 255),
	Background = Color3.fromRGB(22, 22, 28),
	Panel = Color3.fromRGB(32, 32, 42),
	PanelAlt = Color3.fromRGB(42, 42, 54),
	Text = Color3.fromRGB(236, 236, 246),
	SubText = Color3.fromRGB(150, 150, 165),
	Good = Color3.fromRGB(95, 200, 130),
	Bad = Color3.fromRGB(235, 95, 110),
}

return Config
