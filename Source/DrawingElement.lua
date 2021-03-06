local Environment = getgenv()._DrawingEnvironment

local UNDEFINED = "%%UNDEFINED%%"

local Error = {
	DestroyedSet = "The %s property of %s is locked because the object has been destroyed.",
	ReadOnlySet = "Property %s is read-only and cannot be set.",
	InvalidSet = "Invalid property %s (%s expected, got %s)",
	InvalidValue = "Invalid value to property %s (%s expected, got %s)",
	CircularParentRef = "Attempt to set parent of %s to %s would result in a circular reference",
	UnknownProperty = "%s is not a valid member of %s \"%s\"",
	UnknownClass = "Unable to create DrawingElement of type \"%s\"",
	InvalidArgument = "Invalid argument #%d to '%s' (%s expected, got %s)",
}

local Signal = Environment.Signal
local ClassAPI = Environment.ClassAPI

local function AssertIndex(self, Key)
	local Class = self._Properties.Class
	if ClassAPI.DoesPropertyExist(Class, Key) == false then
		error(string.format(Error.UnknownProperty, tostring(Key), Class, self._FullName))
	end
end
local function AssertNewindex(self, Key, Value)
	if self._Destroyed then
		error(string.format(Error.DestroyedSet, tostring(Key), tostring(self._Properties.Name)))
	end

	local Class = self._Properties.Class
	if ClassAPI.IsReadOnly(Class, Key) then
		error(string.format(Error.ReadOnlySet, tostring(Key)))
	end

	local ValidPropertyValue, ExpectedPropertyType = ClassAPI.IsValidPropertyType(Class, Key, Value)
	if ValidPropertyValue == false then
		if ExpectedPropertyType == nil then
			error(string.format(Error.UnknownProperty, tostring(Key), Class, self._FullName))
		else
			error(string.format(Error.InvalidValue, tostring(Key), ExpectedPropertyType, typeof(Value)))
		end
	end
end

local function DeepCopy(Value)
	if typeof(Value) ~= "table" then
		return Value
	end

	local Copy = {}
	for i, v in next, Value do
		Copy[DeepCopy(i)] = DeepCopy(v)
	end

	return Copy
end

local ElementGui = {}
ElementGui.Name = "ElementGui"

local ElementClasses = {}
local function IsElementObject(Object)
	return typeof(Object) == "table" and ElementClasses[Object.Class] == getrawmetatable(Object)
end

local function RecursiveFlatten(Flattened, Count, Children)
	for Child in next, Children do
		Count += 1
		Flattened[Count] = Child

		RecursiveFlatten(Flattened, Count, Child._Children)
	end

	return Flattened
end

local Counter = 0
local function GenerateDebugId()
	Counter += 1
	return Counter
end

local DrawingElement do
	DrawingElement = {}

	-- GuiObject is an abstract class inherited by all DrawingElement objects.
	-- It is not creatable outside of this script.
	local GuiObject do
		GuiObject = {}
		GuiObject.__index = GuiObject

		local ClassPropertiesDraft = ClassAPI.GetDefaultProperties("GuiObject")
		local ClassEventsDraft = ClassAPI.GetEvents("GuiObject")

		local ClassEvents = {}
		for _, EventName in ipairs(ClassEventsDraft) do
			ClassEvents[EventName] = Signal.new()
		end

		function GuiObject.new()
			local Object = setmetatable({
				_Connections = {},
				_DebugId = GenerateDebugId(),
				_Destroyed = false,

				_Properties = DeepCopy(ClassPropertiesDraft),
				_Events = ClassEvents,
			}, GuiObject)

			return Object
		end

		function GuiObject:__newindex(Key, Value)
			debug.profilebegin("GuiObject.__newindex " .. tostring(Key))

			AssertNewindex(self, Key, Value)

			if Key == "Visible" then
				local Parent = self._Properties.Parent
				self:_UpdateVisible(Value, Parent ~= UNDEFINED and Parent._DrawingObject.Visible, Parent)
			elseif Key == "Parent" then
				self:_SetParent(Key, Value)
			elseif Key == "Name" then
				local Props = self._Properties
				Props.Name = Value
				self:_UpdateFullName(Props.Parent)
			elseif Key == "Color" then
				self._Properties.Color = Value
				self._DrawingObject.Color = Value
			elseif Key == "ZIndex" then
				self._Properties.ZIndex = Value
				self._DrawingObject.ZIndex = Value
			end

			debug.profileend()
		end
		function GuiObject:_SetParent(Key, Value)
			assert(Value == nil or IsElementObject(Value), string.format(Error.InvalidSet, tostring(Key), "ElementObject", tostring(Value)))
			debug.profilebegin("__namecall._SetParent " .. self.Class)

			local DidUpdate = false
			if Value ~= nil then
				debug.profilebegin("Verify parent")
				if Value == self._Properties.Parent or Value == self then
					return nil, debug.profileend()
				end

				local NewParent = Value
				while NewParent ~= UNDEFINED do
					if NewParent == self then
						error(string.format(Error.CircularParentRef, self._FullName, Value._FullName))
						return nil, debug.profileend()
					end

					NewParent = NewParent._Properties.Parent
				end
				debug.profileend()

				debug.profilebegin("Update properties")
				DidUpdate = true

				Value._Children[self] = true
				debug.profileend()
			elseif self._Properties.Parent ~= UNDEFINED then
				debug.profilebegin("Update properties (2)")
				DidUpdate = true

				local CurrentParent = self._Properties.Parent
				CurrentParent._Children[self] = nil
				debug.profileend()
			end

			if DidUpdate then
				debug.profilebegin("Update data")
				self._Properties.Parent = Value
				self:_UpdateFullName(Value)
				self:_UpdatePosition()
				debug.profileend()
			end

			debug.profileend()
		end
		function GuiObject:_UpdateVisible(Value, ParentVisible, Parent)
			debug.profilebegin("__namecall._UpdateVisible")
			self._Properties.Visible = Value

			local VisibleValue = Value
			if Parent ~= UNDEFINED then
				VisibleValue = ParentVisible and Value
			end
			self._DrawingObject.Visible = VisibleValue

			for Child in next, self._Children do
				Child:UpdateVisible(Value, VisibleValue, self)
			end
			debug.profileend()
		end
		function GuiObject:_UpdateFullName(ObjectParent)
			debug.profilebegin("__namecall._UpdateFullName")
			local FullName = self._Destroyed and "" or "ElementGui."

			debug.profilebegin("Grab parents")
			local ParentNames = {}
			while ObjectParent ~= UNDEFINED do
				local ParentProps = ObjectParent._Properties
				table.insert(ParentNames, ParentProps.Name)
				ObjectParent = ParentProps.Parent
			end
			debug.profileend()

			debug.profilebegin("Reverse-iterate")
			for Idx = #ParentNames, 1, -1 do
				FullName = FullName .. ParentNames[Idx] .. "."
			end
			debug.profileend()

			self._FullName = FullName .. self._Properties.Name

			for Child in next, self._Children do
				Child:_UpdateFullName(self)
			end
			debug.profileend()
		end
		function GuiObject:_UpdatePosition(ParentPosition, RootPositionProp, PositionProps)
			debug.profilebegin("__namecall._UpdatePosition")

			debug.profilebegin("Get properties")
			local Props = self._Properties

			local RelativePositions = {}
			local AbsolutePositions = {}

			local ParentAbsolutePosition = (ParentPosition or (Props.Parent ~= UNDEFINED and Props.Parent._Properties.AbsolutePosition) or Vector2.zero)
			local DidMove = false
			-- Calculate the new positions.
			-- Some Elements have more than one position property such as triangles & lines, so a for-loop is necessary.
			for PropName, PropValue in next, PositionProps do
				local RelativePosition = PropValue ~= UNDEFINED and PropValue or Props[PropName]
				RelativePositions[PropName] = RelativePosition
				AbsolutePositions[PropName] = ParentAbsolutePosition + RelativePosition

				if AbsolutePositions[PropName] ~= Props["Absolute" .. PropName] then
					DidMove = true
				end
			end
			debug.profileend()

			if DidMove then
				debug.profilebegin("Update drawing object")
				local DrawingObject = self._DrawingObject

				for PropName, PropValue in next, AbsolutePositions do
					DrawingObject[PropName] = PropValue
				end
				debug.profileend()

				debug.profilebegin("Update element properties")
				local ElementAbsolutePosition = AbsolutePositions[RootPositionProp]

				Props.Position = RelativePositions[RootPositionProp]
				Props.AbsolutePositon = ElementAbsolutePosition

				for PropName, PropValue in next, PositionProps do
					Props[PropName] = PropValue
					Props["Absolute" .. PropName] = AbsolutePositions[PropName]
				end
				debug.profileend()

				debug.profilebegin("Update children")
				for ChildElement in next, self._Children do
					ChildElement:_UpdatePosition(ElementAbsolutePosition)
				end
				debug.profileend()
			end
		end

		function GuiObject:GetFullName()
			return self._FullName
		end
		function GuiObject:Destroy()
			debug.profilebegin("__namecall.Destroy")
			self._DrawingObject:Remove()

			for _, Connection in next, self._Connections do
				Connection:DisconnectAll()
			end
			for Child in next, self._Children do
				Child:Destroy()
			end

			local Parent = self._Properties.Parent
			if Parent ~= UNDEFINED then
				Parent._Children[self] = nil
			end

			table.clear(self._Connections)
			table.clear(self._Children)
			self._Destroyed = true

			debug.profileend()
		end
		function GuiObject:GetChildren()
			debug.profilebegin("__namecall.GetChildren")
			local Children = {}
			for Child in next, self._Children do
				table.insert(Children, Child)
			end

			return Children, debug.profileend()
		end
		function GuiObject:GetDescendants()
			debug.profilebegin("__namecall.GetDescendants")
			return RecursiveFlatten({}, 0, self._Children), debug.profileend()
		end
		function GuiObject:FindFirstChild(Name)
			for Object in next, self._Children do
				if Object._Properties.Name == Name then
					return Object
				end
			end
		end
		function GuiObject:GetDebugId()
			return self._DebugId
		end

		GuiObject.__tostring = GuiObject.GetFullName
		ElementClasses.GuiObject = GuiObject
	end

	-- A generalized class-creation function which each child class of the parent `GuiObject` class uses.
	local function CreateChildElement(ConstructorData, ClassName)
		local ClassPropertiesDraft = ClassAPI.GetDefaultProperties(ClassName)
		local ClassEventsDraft = ClassAPI.GetEvents(ClassPropertiesDraft.Class)

		local DrawingObject = Drawing.new(ClassName)
		local ParentClass = DrawingElement[ClassPropertiesDraft.ParentClass].new()

		local Properties = setmetatable(DeepCopy(ClassPropertiesDraft), {
			-- Properties inherited from parent GuiObject class
			__index = ParentClass._Properties
		})

		local ClassEvents = {}
		for _, EventName in ipairs(ClassEventsDraft) do
			ClassEvents[EventName] = Signal.new()
		end

		local Data = {
			_ParentClass = ParentClass,
			_Properties = Properties,
			_DrawingObject = DrawingObject,
			_FullName = ClassPropertiesDraft.Class,

			_Children = {}, -- [Element] = true
		}

		-- Copy over data from parent class onto child class
		for Key, Value in next, ParentClass do
			if Key ~= "_Properties" then
				Data[Key] = Value
			end
		end

		local Object = setmetatable(Data, setmetatable(ConstructorData, ParentClass))
		return Object
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#square
	local Square do
		Square = {}

		function Square.new()
			return CreateChildElement(Square, "Square")
		end

		function Square:__index(Key)
			debug.profilebegin("Square.__index " .. Key)

			AssertIndex(self, Key)

			local FoundProp = self._Properties[Key] or Square[Key] or self._ParentClass[Key]
			if FoundProp == UNDEFINED then
				debug.profileend()
				return nil
			end

			debug.profileend()
			return FoundProp
		end
		function Square:__newindex(Key, Value)
			debug.profilebegin("Square.__newindex " .. Key)

			AssertNewindex(self, Key, Value)

			if Key == "Position" then
				self:_UpdatePosition(nil, Value)
			elseif Key == "Size" then
				self._Properties.Bounds = Value
				self._Properties.Size = Value
				self._DrawingObject.Size = Value
			elseif Key == "Filled" then
				self._Properties.Filled = Value
				self._DrawingObject.Filled = Value
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Square` changes parent or has its `Position` property updated
		function Square:_UpdatePosition(ParentPosition, NewPosition)
			return GuiObject._UpdatePosition(self, ParentPosition, "Position", {
				Position = NewPosition or UNDEFINED
			})
		end

		setmetatable(Square, GuiObject)
		ElementClasses.Square = Square
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#line
	local Line do
		Line = {}

		function Line.new()
			return CreateChildElement(Line, "Line")
		end

		function Line:__index(Key)
			debug.profilebegin("Line.__index " .. tostring(Key))

			AssertIndex(self, Key)

			local FoundProp = self._Properties[Key] or Line[Key] or self._ParentClass[Key]
			if FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Line:__newindex(Key, Value)
			debug.profilebegin("Line.__newindex " .. tostring(Key))

			AssertNewindex(self, Key, Value)

			if Key == "From" or Key == "To" then
				self:_UpdatePosition(nil, {
					[Key] = Value
				})
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Line` changes parent or has its `From` or `To` properties updated
		function Line:_UpdatePosition(ParentPosition, Arguments)
			return GuiObject:_UpdatePosition(ParentPosition, "From", {
				From = Arguments.From or UNDEFINED,
				To = Arguments.To or UNDEFINED,
			})
		end

		setmetatable(Line, GuiObject)
		ElementClasses.Line = Line
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#text
	local Text do
		Text = {}

		function Text.new()
			return CreateChildElement(Text, "Text")
		end

		function Text:__index(Key)
			debug.profilebegin("Text.__index " .. tostring(Key))

			AssertIndex(self, Key)

			local FoundProp = self._Properties[Key] or Text[Key] or self._ParentClass[Key]
			if FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Text:__newindex(Key, Value)
			debug.profilebegin("Text.__newindex " .. tostring(Key))

			AssertNewindex(self, Key, Value)

			if Key == "Position" then
				self:_UpdatePosition(nil, Value)
			elseif Key == "Size" then
				self._Properties.Size = Value
			elseif Key == "Text" then
				self._Properties.Text = Value
				self._DrawingObject.Text = Value

				self._Properties.Bounds = self._DrawingObject.TextBounds
				self._Properties.TextBounds = self._DrawingObject.TextBounds
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Text` changes parent or has its `Position` property updated
		function Text:_UpdatePosition(ParentPosition, NewPosition)
			return GuiObject._UpdatePosition(self, ParentPosition, "Position", {
				Position = NewPosition or UNDEFINED
			})
		end

		setmetatable(Text, GuiObject)
		ElementClasses.Text = Text
	end

	-- https://x.synapse.to/docs/reference/drawing_lib.html#triangle
	local Triangle do
		Triangle = {}

		function Triangle.new()
			return CreateChildElement(Triangle, "Triangle")
		end

		function Triangle:__index(Key)
			debug.profilebegin("Triangle.__index " .. tostring(Key))

			AssertIndex(self, Key)

			local FoundProp = self._Properties[Key] or Triangle[Key] or self._ParentClass[Key]
			if FoundProp == UNDEFINED then
				return nil, debug.profileend()
			end

			return FoundProp, debug.profileend()
		end
		function Triangle:__newindex(Key, Value)
			debug.profilebegin("Triangle.__newindex " .. tostring(Key))

			AssertNewindex(self, Key, Value)

			if Key == "PointA" or Key == "PointB" or Key == "PointC" then
				self:_UpdatePosition({
					[Key] = Value
				})
				self:_UpdatePosition(nil, Value)
			elseif ClassAPI.IsValidProperty(self._Properties.Class, Key) then
				self._Properties[Key] = Value
				self._DrawingObject[Key] = Value
			else
				GuiObject.__newindex(self, Key, Value)
			end

			debug.profileend()
		end

		-- Called whenever `Triangle` changes parent or has its `PointA`, `PointB` or `PointC` properties updated
		function Triangle:_UpdatePosition(ParentPosition, Arguments)
			return GuiObject._UpdatePosition(self, ParentPosition, "PointB", {
				PointA = Arguments.PointA or UNDEFINED,
				PointB = Arguments.PointB or UNDEFINED,
				PointC = Arguments.PointC or UNDEFINED,
			})
		end

		setmetatable(Triangle, GuiObject)
		ElementClasses.Triangle = Triangle
	end

	function DrawingElement.new(Class)
		assert(typeof(Class) == "string", string.format(Error.InvalidArgument, "1", "DrawingElement.new", "string", typeof(Class)))
		assert(ElementClasses[Class] ~= nil and ClassAPI.IsCreatable(Class), string.format(Error.UnknownClass, Class))

		return ElementClasses[Class].new()
	end
end

return DrawingElement