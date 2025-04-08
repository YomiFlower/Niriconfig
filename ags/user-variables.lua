return {
	dock = {
		pinned_apps = {
			"nautilus",
			"ghostty",
			"zen",
			"telegram",
			"obs",
			"zed",
			"resources",
		},
	},
	github = {
		username = "YomiFlower",
	},
	monitor = {
		mode = "specific", -- Can be "primary", "all", or "specific"
		specific_monitor = 2,
	},
	profile = {
		picture = os.getenv("HOME") .. "/Downloads/pxArt(1).png",
	},
	media = {
		preferred_players = {
			"zen",
			"firefox",
			"spotify",
		},
	},
	display = {
		night_light_temp_initial = 3500,
	},
}
