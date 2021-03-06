local Module = {}

local UNDEFINED = "%%UNDEFINED%%"

local API = {
	GuiObject = {
		NotCreatable = true,
		Properties = {
			Class = {
				Value = "GuiObject",
				Types = {"string"},
				ReadOnly = true,
			},
			Visible = {
				Value = false,
				Types = {"boolean"},
			},
			ZIndex = {
				Value = 1,
				Types = {"number"},
			},
			Transparency = {
				Value = 1,
				Types = {"number"},
			},
			Color = {
				Value = Color3.new(0, 0, 0),
				Types = {"Color3"},
			},
			Parent = {
				Value = UNDEFINED,
				Types = {"GuiObject"},
			},
			AnchorPoint = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			Position = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			Name = {
				Value = "GuiObject",
				Types = {"string"},
			},
			AbsolutePosition = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			Bounds = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			}
		},
		Events = {
			"PropertyChanged",
			"AncestryChanged",
		},
	},

	Square = {
		ParentClass = "GuiObject",

		Properties = {
			Class = {
				Value = "Square",
				Types = {"string"},
				ReadOnly = true,
			},
			Thickness = {
				Value = 1,
				Types = {"number"},
			},
			Filled = {
				Value = false,
				Types = {"boolean"},
			},
			Size = {
				Value = Vector2.new(16, 16),
				Types = {"Vector2"}
			}
		},
		Events = {

		},
	},

	Line = {
		ParentClass = "GuiObject",

		Properties = {
			Class = {
				Value = "Line",
				Types = {"string"},
				ReadOnly = true,
			},
			Thickness = {
				Value = 1,
				Types = {"number"},
			},
			From = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			To = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			AbsoluteFrom = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			AbsoluteTo = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			Position = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
		},
		Events = {

		},
	},

	Text = {
		ParentClass = "GuiObject",

		Properties = {
			Class = {
				Value = "Text",
				Types = {"string"},
				ReadOnly = true,
			},
			Text = {
				Value = "",
				Types = {"string"},
			},
			TextSize = {
				Value = 16,
				Types = {"number"},
			},
			Center = {
				Value = false,
				Types = {"boolean"},
			},
			Outline = {
				Value = false,
				Types = {"boolean"},
			},
			OutlineColor = {
				Value = Color3.new(0, 0, 0),
				Types = {"Color3"},
			},
			TextBounds = {
				Value = Vector2.new(0, 16),
				Types = {"Vector2"},
				ReadOnly = true,
			},
			Font = {
				Value = Drawing.Fonts.UI,
				Types = {"number"},
			},
			Size = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
		},
		Events = {

		},
	},

	Triangle = {
		ParentClass = "GuiObject",

		Properties = {
			Class = {
				Value = "Triangle",
				Types = {"string"},
				ReadOnly = true,
			},
			PointA = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			PointB = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			PointC = {
				Value = Vector2.zero,
				Types = {"Vector2"},
			},
			AbsolutePointA = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			AbsolutePointB = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			AbsolutePointC = {
				Value = Vector2.zero,
				Types = {"Vector2"},
				ReadOnly = true,
			},
			Filled = {
				Value = false,
				Types = {"boolean"},
			},
		},
		Events = {

		},
	},
}


local PerformPropertyAction; PerformPropertyAction = function(Class, Name, Action)
	local ClassAPI = API[Class]
	local PropertyAPI = ClassAPI.Properties

	if PropertyAPI[Name] ~= nil then
		return Action(PropertyAPI[Name])
	elseif ClassAPI.ParentClass ~= nil then
		return PerformPropertyAction(ClassAPI.ParentClass, Name, Action)
	else
		return false
	end
end

function Module.DoesPropertyExist(Class, Name)
	return PerformPropertyAction(Class, Name, function()
		return true
	end)
end

function Module.IsValidPropertyType(Class, Name, Value)
	local InputType = typeof(Value)
	return PerformPropertyAction(Class, Name, function(ValueData)
		for _, Type in next, ValueData.Types do
			if Type == InputType then
				return true
			end
		end

		return false, ValueData.Types[1]
	end)
end

function Module.IsReadOnly(Class, Name)
	return PerformPropertyAction(Class, Name, function(ValueData)
		return ValueData ~= nil and ValueData.ReadOnly == true
	end)
end

function Module.GetDefaultProperties(Class)
	local PropertiesAPI = API[Class].Properties
	local DefaultProperties = {}

	for Name, PropertyData in next, PropertiesAPI do
		DefaultProperties[Name] = PropertyData.Value
	end

	return DefaultProperties
end
function Module.GetEvents(Class)
	return API[Class].Events
end
function Module.IsCreatable(Class)
	return API[Class].IsCreatable
end
function Module.IsValidProperty(Class, PropertyName)
	return API[Class].Properties[PropertyName] ~= nil
end

return Module