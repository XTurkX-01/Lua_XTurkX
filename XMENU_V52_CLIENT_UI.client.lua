--!strict
--[[
	X MENU V52 — CLIENT ARAYÜZÜ  (tek dosya, yapıştır-çalıştır)

	İçerik
	  Bölüm 1  UIKit            → toast, buton, cooldown butonu, pencere, etiket, slider
	  Bölüm 2  Yetenek çubuğu  → server yeteneklerinin butonları (süre/cooldown sunucuda)
	  Bölüm 3  Klavye           → Z hız · X zıplama · C kalkan · V iyileşme
	  Bölüm 4  Ayarlar menüsü  → ses, parlaklık, kamera mesafesi, FOV, efekt kalitesi, arayüz ölçeği
	  Bölüm 5  Yönetici paneli → speed/god/heal/tp/bring/kick (yalnızca yetkili görünümü olan hesapta)

	Sunucu sözleşmesi (server oluşturur, client BEKLER — hiçbir remote oluşturulmaz)
	  ReplicatedStorage/Remotes/UseAbility      : FireServer(abilityId: string)
	  ReplicatedStorage/Remotes/AbilityResult   : (abilityId, ok, reason, cooldownRemaining)
	  ReplicatedStorage/Remotes/Notify          : (message: string)
	  ReplicatedStorage/Remotes/AdminCommand    : FireServer(command: string, argument: string)
	  ReplicatedStorage/Remotes/RequestRejoin   : FireServer()

	İlkeler
	  • Client sadece İSTEK yollar; süre/cooldown/yetki/parametre sunucuda belirlenir.
	  • Bildirimin tek kaynağı: AbilityResult → yetenek çubuğu, Notify → yönetici paneli.
	  • Ayarlar yalnızca görünüm/ses; oyuna yetki vermez ve kaydedilmez.
	  • Her değer uygulanmadan önce sınırlanır (math.clamp).
	  • Panel ve butonlar mobil önceliklidir (Scale tabanlı, ≥44 px dokunma hedefi).

	Kurulum
	  • StarterPlayer > StarterPlayerScripts içine LocalScript olarak koy, OR
	  • Play modundayken oyuncuyu seçip "View → Command Bar" ile çalıştır.
	  • Yönetici paneli için Bölüm 5'teki LOCAL_ADMIN_USER_IDS tablosuna kendi
	    UserId'ni yaz (sunucudaki ADMIN_USER_IDS ile aynı olmalı).

	Not: Script tekrar çalıştırılırsa önceki arayüzü temizler (üst üste binmez).
]]

-- ============================================================================
-- ORTAK: servisler, temizlik kaydı ve remote'lar
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Tekrar çalıştırmada üst üste binmesin: eski arayüzü yok et.
local REGISTRY_KEY = "XMENU_V52_CLIENT_UI"
local sharedGlobals: any = _G
local previous = sharedGlobals[REGISTRY_KEY]
if type(previous) == "table" and type(previous.Cleanup) == "function" then
	pcall(previous.Cleanup)
end
local oldGui = playerGui:FindFirstChild("UIKitGui")
if oldGui ~= nil then
	oldGui:Destroy()
end

-- Bağlantıları topluyoruz (yeniden çalıştırmada hepsi kesilsin).
local connections: { RBXScriptConnection } = {}
local function track(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

-- Remote'lar server'da oluşturulur; burada sadece beklenir.
local function waitRemote(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes == nil then
		return nil
	end
	local remote = remotes:FindFirstChild(name)
	if remote ~= nil and remote:IsA("RemoteEvent") then
		return remote :: RemoteEvent
	end
	return nil
end

local useAbility = waitRemote("UseAbility")
local abilityResult = waitRemote("AbilityResult")
local notifyEvent = waitRemote("Notify")
local adminCommand = waitRemote("AdminCommand")
local rejoinRequest = waitRemote("RequestRejoin")

--[[
	BÖLÜM 1 — UIKit (arayüz kiti)

	Mobil uyumlu küçük arayüz kitaplığı:
	  UIKit.toast(mesaj)                         ekranın üstünde kısa bildirim (en fazla 3 tane)
	  UIKit.button(parent, yazı, fonksiyon)      dokunması kolay, çift basmaya karşı korumalı buton
	  UIKit.cooldownButton(parent, yazı, fn)     cooldown dolumu + geri sayım + "aktif" çerçevesi
	  UIKit.abilityBar(liste, useRemote, result) yetenek çubuğu; server cevaplarına bağlanır
	  UIKit.window(başlık)                       kayan panel (başlık + X + kaydırılabilir gövde)
	  UIKit.label(parent, yazı)                  panel satırı etiketi
	  UIKit.slider(min, max, step, fn)           sürüklemeli sayı seçici (yazmadan değer seçme)

	Tasarım kuralları
	• Boyutlar Scale ile verilir; en küçük dokunma hedefi UISizeConstraint ile ~44 px.
	• ScreenGui.ResetOnSpawn = false (ölünce arayüz sıfırlanmaz).
	• Her Connect için temizlik: cooldown döngüsü bitince/yok edilince kapanır.
	• Server'a sadece yetenek ADI yollanır. Süre/cooldown client'ta sadece gösterim içindir.

	Görsel boyutlar, renkler ve yerleşim Studio'da kendi ekranında denenmelidir.
]]


local UIKit = {}

local THEME = {
	Panel = Color3.fromRGB(38, 41, 50),
	Overlay = Color3.fromRGB(0, 0, 0),
	Accent = Color3.fromRGB(64, 156, 255),
	AccentDark = Color3.fromRGB(48, 116, 196),
	Ready = Color3.fromRGB(46, 160, 100),
	Text = Color3.fromRGB(240, 240, 245),
}

-- Glassmorphism: arka plan yarı saydam, kenarlık neon vurgulu.
local GLASS_TRANSPARENCY = 0.18
local GLASS_HOVER_TRANSPARENCY = 0.1
local WINDOW_OPEN_TIME = 0.18

local MIN_TOUCH_PX = 44
local MAX_TOASTS = 3
local MAX_TOAST_LENGTH = 200
local DEFAULT_DEBOUNCE = 0.2
local REFRESH_INTERVAL = 0.1 -- cooldown görünümü saniyede ~10 kez yenilenir

local screenGui: ScreenGui? = nil
local toastHolder: Frame? = nil
local activeToasts: { Frame } = {}

--- Tüm UIKit öğelerinin durduğu ScreenGui (yoksa oluşturur).
function UIKit.getGui(): ScreenGui
	if screenGui ~= nil and screenGui.Parent ~= nil then
		return screenGui
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("UIKitGui")
	if existing ~= nil and existing:IsA("ScreenGui") then
		screenGui = existing
		return existing
	end

	local gui = Instance.new("ScreenGui") :: ScreenGui
	gui.Name = "UIKitGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = playerGui
	screenGui = gui
	return gui
end

local function getToastHolder(): Frame
	if toastHolder ~= nil and toastHolder.Parent ~= nil then
		return toastHolder
	end

	local holder = Instance.new("Frame") :: Frame
	holder.Name = "Toasts"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.02)
	holder.Size = UDim2.fromScale(0.7, 0.3)

	local layout = Instance.new("UIListLayout") :: UIListLayout
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder

	local limit = Instance.new("UISizeConstraint") :: UISizeConstraint
	limit.MaxSize = Vector2.new(460, 400)
	limit.Parent = holder

	holder.Parent = UIKit.getGui()
	toastHolder = holder
	return holder
end

--- Ekranın üstünde kısa bildirim. Aynı anda en fazla 3 tane; fazlası eskiyi atar.
function UIKit.toast(message: string, seconds: number?): ()
	local holder = getToastHolder()

	while #activeToasts >= MAX_TOASTS do
		local oldest = table.remove(activeToasts, 1)
		if oldest ~= nil then
			oldest:Destroy()
		end
	end

	local label = Instance.new("TextLabel") :: TextLabel
	label.Name = "Toast"
	label.Size = UDim2.new(1, 0, 0, 36)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = THEME.Panel
	label.TextColor3 = THEME.Text
	label.TextSize = 18
	label.TextWrapped = true
	label.Font = Enum.Font.GothamMedium
	label.Text = string.sub(message, 1, MAX_TOAST_LENGTH)

	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	label.Parent = holder
	table.insert(activeToasts, label)

	task.delay(seconds or 3, function()
		local index = table.find(activeToasts, label)
		if index ~= nil then
			table.remove(activeToasts, index)
		end
		if label.Parent ~= nil then
			label:Destroy()
		end
	end)
end

--- Dokunması kolay buton. Çift basmaya karşı debounce (varsayılan 0.2 sn).
function UIKit.button(
	parent: Instance,
	text: string,
	onActivated: () -> (),
	debounceSeconds: number?
): TextButton
	local button = Instance.new("TextButton") :: TextButton
	button.Name = "UIKitButton"
	button.Size = UDim2.fromOffset(96, 56)
	button.BackgroundColor3 = THEME.Panel
	button.TextColor3 = THEME.Text
	button.TextSize = 18
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.AutoButtonColor = true

	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	-- Küçük ekranda bile parmakla basılabilsin.
	local minSize = Instance.new("UISizeConstraint") :: UISizeConstraint
	minSize.MinSize = Vector2.new(MIN_TOUCH_PX, MIN_TOUCH_PX)
	minSize.Parent = button

	local debounce = debounceSeconds or DEFAULT_DEBOUNCE
	local lastPress = -math.huge
	button.Activated:Connect(function()
		local now = os.clock()
		if now - lastPress < debounce then
			return
		end
		lastPress = now
		onActivated()
	end)

	-- Hover efekti (fare üzerine gelince renk değişir).
	local baseColor = THEME.Panel
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = THEME.AccentDark
		button.BackgroundTransparency = GLASS_HOVER_TRANSPARENCY
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = baseColor
		button.BackgroundTransparency = GLASS_TRANSPARENCY
	end)

	button.BackgroundTransparency = GLASS_TRANSPARENCY
	button.Parent = parent
	return button
end

export type CooldownButton = {
	Button: TextButton,
	Start: (self: CooldownButton, seconds: number) -> (),
	SetActive: (self: CooldownButton, seconds: number) -> (),
	ClearActive: (self: CooldownButton) -> (),
	IsReady: (self: CooldownButton) -> boolean,
	Destroy: (self: CooldownButton) -> (),
}

--- Cooldown dolumu, geri sayım ve "aktif" çerçevesi olan buton.
function UIKit.cooldownButton(parent: Instance, text: string, onActivated: () -> ()): CooldownButton
	local button = UIKit.button(parent, text, onActivated)
	button.ClipsDescendants = true

	-- Yukarıdan aşağı küçülen koyu katman = kalan cooldown.
	local overlay = Instance.new("Frame") :: Frame
	overlay.Name = "Cooldown"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = THEME.Overlay
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Parent = button

	local countdown = Instance.new("TextLabel") :: TextLabel
	countdown.Name = "Countdown"
	countdown.Size = UDim2.fromScale(1, 1)
	countdown.BackgroundTransparency = 1
	countdown.TextColor3 = THEME.Text
	countdown.TextSize = 22
	countdown.Font = Enum.Font.GothamBold
	countdown.Text = ""
	countdown.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = THEME.Ready
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = button

	local readyAt = 0
	local activeUntil = 0
	local total = 1
	local connection: RBXScriptConnection? = nil
	local accumulator = 0

	local function stopLoop()
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end

	local function refresh()
		local now = os.clock()
		local remaining = readyAt - now

		if remaining > 0 then
			overlay.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
			countdown.Text = tostring(math.ceil(remaining))
		else
			overlay.Size = UDim2.fromScale(1, 0)
			countdown.Text = ""
		end

		local active = now < activeUntil
		stroke.Enabled = active

		if remaining <= 0 and not active then
			stopLoop()
		end
	end

	local function startLoop()
		if connection ~= nil then
			return
		end
		accumulator = 0
		connection = RunService.Heartbeat:Connect(function(dt: number)
			accumulator += dt
			if accumulator >= REFRESH_INTERVAL then
				accumulator = 0
				refresh()
			end
		end)
	end

	local self: CooldownButton = {
		Button = button,

		Start = function(_self: CooldownButton, seconds: number)
			if seconds ~= seconds or seconds <= 0 then
				readyAt = 0
			else
				total = seconds
				readyAt = os.clock() + seconds
			end
			refresh()
			if readyAt > os.clock() then
				startLoop()
			end
		end,

		SetActive = function(_self: CooldownButton, seconds: number)
			if seconds ~= seconds or seconds <= 0 then
				return
			end
			activeUntil = os.clock() + seconds
			refresh()
			startLoop()
		end,

		ClearActive = function(_self: CooldownButton)
			activeUntil = 0
			refresh()
		end,

		IsReady = function(_self: CooldownButton): boolean
			return os.clock() >= readyAt
		end,

		Destroy = function(_self: CooldownButton)
			stopLoop()
			button:Destroy()
		end,
	}

	return self
end

export type AbilityInfo = {
	Id: string,
	Label: string,
	Duration: number, -- "aktif" çerçevesinin süresi (sadece gösterim)
}--- Yetenek çubuğu. Temizleme fonksiyonu döner (çağırırsan çubuk ve bağlantılar kaldırılır).
function UIKit.abilityBar(abilities: { AbilityInfo }, useRemote: RemoteEvent, resultRemote: RemoteEvent): () -> ()
	local container = Instance.new("Frame") :: Frame
	container.Name = "AbilityBar"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.fromScale(0.5, 0.97)
	container.Size = UDim2.fromScale(0.8, 0.14)
	container.BackgroundTransparency = 1

	local layout = Instance.new("UIListLayout") :: UIListLayout
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	local limit = Instance.new("UISizeConstraint") :: UISizeConstraint
	limit.MaxSize = Vector2.new(520, 96)
	limit.Parent = container

	local buttons: { [string]: CooldownButton } = {}
	local infoById: { [string]: AbilityInfo } = {}

	for _, info in abilities do
		infoById[info.Id] = info
		buttons[info.Id] = UIKit.cooldownButton(container, info.Label, function()
			useRemote:FireServer(info.Id)
		end)
	end

	local resultConnection = resultRemote.OnClientEvent:Connect(function(abilityId: unknown, ok: unknown, reason: unknown, remaining: unknown)
		-- Server güvenilir ama yine de tipleri kontrol et (bozuk veri arayüzü çökertmesin).
		if typeof(abilityId) ~= "string" or typeof(remaining) ~= "number" then
			return
		end
		local cooldown = buttons[abilityId]
		local info = infoById[abilityId]
		if cooldown == nil or info == nil then
			return
		end

		if ok == true then
			cooldown:Start(remaining)
			if info.Duration > 0 then
				cooldown:SetActive(info.Duration)
			end
		elseif reason == "Cooldown" then
			cooldown:Start(remaining)
		elseif reason == "Dead" then
			UIKit.toast("Ölüyken kullanılamaz")
		else
			UIKit.toast("Şu an kullanılamıyor")
		end
	end)

	-- Yeniden doğunca "aktif" çerçeveleri sıfırlanır (server etkileri de sıfırlar). Cooldown KORUNUR.
	local characterConnection = Players.LocalPlayer.CharacterAdded:Connect(function()
		for _, cooldown in buttons do
			cooldown:ClearActive()
		end
	end)

	container.Parent = UIKit.getGui()

	return function()
		resultConnection:Disconnect()
		characterConnection:Disconnect()
		for _, cooldown in buttons do
			cooldown:Destroy()
		end
		container:Destroy()
	end
end

-- ---------------------------------------------------------------------------
-- Pencere, etiket ve kaydırıcı (ayarlar / admin ekranları için ortak kabuk)
-- ---------------------------------------------------------------------------

export type WindowOptions = {
	Title: string,
	Name: string?,
	WidthScale: number?,
	HeightScale: number?,
}

export type Window = {
	Frame: Frame,
	Body: Frame,
	SetTitle: (self: Window, text: string) -> (),
	SetVisible: (self: Window, visible: boolean) -> (),
	IsVisible: (self: Window) -> boolean,
	Destroy: (self: Window) -> (),
}

--- Ekran ortasında kayan panel: başlık, büyük X butonu, kaydırılabilir gövde.
--- İçeriği `Window.Body` çerçevesine ekle (dikey UIListLayout ile dizilir).
function UIKit.window(options: WindowOptions): Window
	local widthScale = options.WidthScale or 0.86
	local heightScale = options.HeightScale or 0.72

	local frame = Instance.new("Frame") :: Frame
	frame.Name = options.Name or "UIKitWindow"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(widthScale, heightScale)
	frame.BackgroundColor3 = THEME.Panel
	frame.BackgroundTransparency = GLASS_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = UIKit.getGui()

	-- Neon kenarlık (glassmorphism çerçevesi)
	local border = Instance.new("UIStroke") :: UIStroke
	border.Color = THEME.Accent
	border.Thickness = 1.5
	border.Transparency = 0.45
	border.Parent = frame

	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	-- Küçük telefonda da okunur, büyük ekranda dağılmasın.
	local limit = Instance.new("UISizeConstraint") :: UISizeConstraint
	limit.MinSize = Vector2.new(260, 220)
	limit.MaxSize = Vector2.new(520, 620)
	limit.Parent = frame

	local titleLabel = Instance.new("TextLabel") :: TextLabel
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(16, 12)
	titleLabel.Size = UDim2.new(1, -76, 0, 28)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = options.Title
	titleLabel.TextColor3 = THEME.Text
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = frame

	-- Kapatma butonu dokunma hedefi olarak büyük (48 px).
	local closeButton = Instance.new("TextButton") :: TextButton
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.fromOffset(48, 48)
	closeButton.BackgroundTransparency = 1
	closeButton.Text = "X"
	closeButton.TextColor3 = THEME.Text
	closeButton.TextSize = 22
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = frame

	local content = Instance.new("ScrollingFrame") :: ScrollingFrame
	content.Name = "Content"
	content.Position = UDim2.fromOffset(12, 52)
	content.Size = UDim2.new(1, -24, 1, -64)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = frame

	local body = Instance.new("Frame") :: Frame
	body.Name = "Body"
	body.Size = UDim2.new(1, -8, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = content

	local layout = Instance.new("UIListLayout") :: UIListLayout
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	local closeConnection: RBXScriptConnection
	local self: Window = {
		Frame = frame,
		Body = body,

		SetTitle = function(_self: Window, text: string)
			titleLabel.Text = text
		end,

		SetVisible = function(_self: Window, visible: boolean)
			if visible then
				frame.Visible = true
				frame.BackgroundTransparency = 0.4
				frame.Size = UDim2.fromScale(widthScale * 0.94, heightScale * 0.94)
				local tween = TweenService:Create(
					frame,
					TweenInfo.new(WINDOW_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(widthScale, heightScale), BackgroundTransparency = GLASS_TRANSPARENCY }
				)
				tween:Play()
			else
				local tween = TweenService:Create(
					frame,
					TweenInfo.new(WINDOW_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = UDim2.fromScale(widthScale * 0.94, heightScale * 0.94), BackgroundTransparency = 0.4 }
				)
				tween.Completed:Connect(function()
					frame.Visible = false
				end)
				tween:Play()
			end
		end,

		IsVisible = function(_self: Window): boolean
			return frame.Visible
		end,

		Destroy = function(_self: Window)
			closeConnection:Disconnect()
			frame:Destroy()
		end,
	}

	closeConnection = closeButton.Activated:Connect(function()
		self:SetVisible(false)
	end)

	return self
end

--- Panel satırı etiketi. `UIKit.button` ile yatayda kullanılır.
function UIKit.label(parent: Instance, text: string): TextLabel
	local label = Instance.new("TextLabel") :: TextLabel
	label.Name = "UIKitLabel"
	label.Size = UDim2.new(1, 0, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = THEME.Text
	label.TextSize = 16
	label.Font = Enum.Font.GothamSemibold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

export type SliderOptions = {
	Min: number,
	Max: number,
	Step: number,
	Value: number?,
	OnChange: (value: number) -> (),
}

export type Slider = {
	Frame: Frame,
	GetValue: (self: Slider) -> number,
	SetValue: (self: Slider, value: number) -> (),
	Destroy: (self: Slider) -> (),
}

--- Sürüklemeli sayı seçici (admin hız komutu vb. için).
--- Mobilde yazmak yerine sürüklenir; değer adıma (step) yuvarlanır.
function UIKit.slider(options: SliderOptions): Slider
	local minValue = options.Min
	local maxValue = options.Max
	local step = options.Step
	local value = math.clamp(options.Value or minValue, minValue, maxValue)

	local frame = Instance.new("Frame") :: Frame
	frame.Name = "UIKitSlider"
	frame.Size = UDim2.new(1, 0, 0, 44)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local track = Instance.new("Frame") :: Frame
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 0, 0.5, 0)
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = THEME.Overlay
	track.BackgroundTransparency = 0.35
	track.BorderSizePixel = 0
	track.Parent = frame

	local fill = Instance.new("Frame") :: Frame
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = THEME.Accent
	fill.BorderSizePixel = 0
	fill.Parent = track

	local thumb = Instance.new("TextButton") :: TextButton
	thumb.Name = "Thumb"
	thumb.AnchorPoint = Vector2.new(0, 0.5)
	thumb.Size = UDim2.fromOffset(44, 44)
	thumb.BackgroundColor3 = THEME.Accent
	thumb.Text = ""
	thumb.BorderSizePixel = 0
	thumb.Parent = frame

	local connections: { RBXScriptConnection } = {}
	local dragging = false

	local function apply(newValue: number)
		value = math.clamp(newValue, minValue, maxValue)
		local ratio = if maxValue > minValue then (value - minValue) / (maxValue - minValue) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		thumb.Position = UDim2.new(ratio, -22, 0.5, 0)
		options.OnChange(value)
	end

	local function valueFromX(x: number): number
		local left = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return value
		end
		local ratio = math.clamp((x - left) / width, 0, 1)
		local raw = minValue + ratio * (maxValue - minValue)
		if step >= 1 then
			raw = math.floor(raw / step + 0.5) * step
		end
		return raw
	end

	table.insert(connections, thumb.InputBegan:Connect(function(input: InputObject)
		dragging = true
		apply(valueFromX(input.Position.X))
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			apply(valueFromX(input.Position.X))
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(_input: InputObject)
		dragging = false
	end))

	apply(value)

	local self: Slider = {
		Frame = frame,
		GetValue = function(_self: Slider): number
			return value
		end,
		SetValue = function(_self: Slider, newValue: number)
			apply(newValue)
		end,
		Destroy = function(_self: Slider)
			for _, connection in connections do
				connection:Disconnect()
			end
			connections = {}
			frame:Destroy()
		end,
	}

	return self
end


--[[
	BÖLÜM 2 — Yetenek çubuğu

	Yetenek çubuğunu kurar. UIKit ModuleScript'i AYNI klasörde (StarterPlayerScripts) olmalı.
	Remote'ları server oluşturur; burada sadece beklenir.

	"Değiştir, ekleme" kuralı gereği bildirim işleme TEK yerde olmalı:
	• AbilityResult'ı UIKit.abilityBar dinler (cooldown/aktif gösterge).
	• Eski AbilityClient'taki AbilityResult bildirimi SİLİNMİŞTİR (çift toast).
	• Notify dinleyicisi AdminClient'tadır: admin cevabı panelde görünür,
	  rejoin uyarısı ise toast olarak çıkar.
	• UseAbility'i iki yer tetikler: klavye (AbilityClient) ve çubuktaki
	  butonlar. Bu iki tetikleyici farklı olaylardır; sunucu ayrıca
	  token-bucket limit uygular.
]]

-- Duration = "aktif" çerçevesinin süresi (sadece gösterim). Gerçek süreyi server belirler.
local cleanupAbilityBar: (() -> ())? = nil

if useAbility ~= nil and abilityResult ~= nil then
	cleanupAbilityBar = UIKit.abilityBar({
	{ Id = "SpeedBoost", Label = "Hız", Duration = 8 },
	{ Id = "HighJump", Label = "Zıpla", Duration = 8 },
	{ Id = "Shield", Label = "Kalkan", Duration = 5 },
	{ Id = "Heal", Label = "İyileş", Duration = 0 },
	}, useAbility, abilityResult)
else
	warn("[X MENU UI] UseAbility/AbilityResult bulunamadı — sunucu modülleri yüklü mü?")
end

--[[
	BÖLÜM 3 — Klavye ile yetenek (Z hız · X zıplama · C kalkan · V iyileşme)

	Sadece İSTEK gönderir ve bildirimleri gösterir. Hız/zıplama/hasar gibi
	hiçbir şeyi client belirlemez; server karar verir.

	Tuşlar: Z = hız, X = yüksek zıplama, C = kalkan, V = iyileşme

	DEĞİŞTİRME (bkz. roblox_ai_destek_paketi.md §1.6 — "Değiştir, ekleme" kuralı):
	• AbilityResult bloğu SİLİNDİ. Çubuk (UIClient/UIKit.abilityBar) aynı
	  cevabı dinliyordu; iki dinleyici "Cooldown" uyarısını iki kez gösteriyordu.
	• Notify bloğu SİLİNDİ. Admin cevabı artık AdminClient panelinde,
	  rejoin uyarısı ise AdminClient'ın toast'ında gösteriliyor.
	  (Bildirimin tek kaynağı kuralı.)
	• Klavye tetikleyicisine 0.2 sn debounce eklendi (ui_baglanti_belgesi.md §2).
	  Sunucu saniyede ~4 istek kabul ediyor; fazlası sessizce düşürülüyor.
	• RequestRejoin değişkeni korundu; buton SettingsClient'ta bağlı.
]]

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Z] = "SpeedBoost",
	[Enum.KeyCode.X] = "HighJump",
	[Enum.KeyCode.C] = "Shield",
	[Enum.KeyCode.V] = "Heal",
}

local CLIENT_DEBOUNCE = 0.2
local lastPress = -math.huge

if useAbility ~= nil then
	track(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end

		local abilityId = KEYS[input.KeyCode]
		if abilityId == nil then
			return
		end

		local now = os.clock()
		if now - lastPress < CLIENT_DEBOUNCE then
			return
		end
		lastPress = now

		useAbility:FireServer(abilityId)
	end))
end

-- AbilityResult ve Notify dinleyicileri bilerek YOK (tek bildirim kaynağı):
-- AbilityResult'ı Bölüm 2 (yetenek çubuğu), Notify'ı Bölüm 5 (yönetici paneli) dinler.

--[[
	BÖLÜM 4 — Ayarlar menüsü

	AYARLAR MENÜSÜ (ui_baglanti_belgesi.md §4)

	• Tamamen client taraflıdır: hiçbir remote çağırmaz, sunucuya veri yazmaz.
	• Ayar oyuna hiçbir yetki vermez; sadece görünüm ve ses.
	• Şu an KALICI DEĞİLDİR: oyundan çıkınca sıfırlanır. Kalıcı olması için
	  server'da SettingsService + DataStore gerekir (henüz yazılmadı).
	• Her değer uygulanmadan önce math.clamp ile sınırlanır.
	• "Varsayılana dön" oyunun script başlarki değerlerine geri döner.
	• Karakter yeniden doğunca / kamera değişince ayarlar tekrar uygulanır.

	Sunucu sözleşmesiyle ilgili tek istisna: "Yeniden bağlan" butonu
	RequestRejoin remote'unu çağırır (rejoin servisini tetikler). Bu bir
	ayar değil, bir eylemdir.
]]


--[[
	Sınırlar (client tahmini; oyunun kendi limitleri ayrıca geçerlidir)
]]

local VOLUME_MIN = 0
local VOLUME_MAX = 1
local VOLUME_STEP = 0.05

local BRIGHTNESS_MIN = 0
local BRIGHTNESS_MAX = 4
local BRIGHTNESS_STEP = 0.1

local ZOOM_MIN = 4
local ZOOM_MAX = 60
local ZOOM_STEP = 1

local FOV_MIN = 60
local FOV_MAX = 100
local FOV_STEP = 1

local UI_SCALE_MIN = 0.8
local UI_SCALE_MAX = 1.25
local UI_SCALE_STEP = 0.05

local MIN_ZOOM_FLOOR = 6 -- CameraMinZoomDistance bunun altına inmesin

--[[
	Varsayılanlar: oyunun script başlarki değerleri ("Varsayılana dön" bunlara döner)
]]

local defaultBrightness = Lighting.Brightness
local defaultShadows = Lighting.GlobalShadows
local defaultMaxZoom = player.CameraMaxZoomDistance
local defaultMinZoom = player.CameraMinZoomDistance

local camera = workspace.CurrentCamera
local defaultFov = if camera ~= nil then camera.FieldOfView else 70

local function findSoundGroup(names: { string }): SoundGroup?
	for _, child in SoundService:GetChildren() do
		if child:IsA("SoundGroup") then
			local lowerName = string.lower(child.Name)
			for _, wanted in names do
				if lowerName == wanted then
					return child :: SoundGroup
				end
			end
		end
	end
	return nil
end

local musicGroup = findSoundGroup({ "music", "müzik", "bgm", "background", "ambient" })
local effectsGroup = findSoundGroup({ "sfx", "effects", "efekt", "sound", "ui", "soundfx" })

local defaultMusicVolume = if musicGroup ~= nil then musicGroup.Volume else 1
local defaultEffectsVolume = if effectsGroup ~= nil then effectsGroup.Volume else 1

--[[
	Uygulama fonksiyonları
]]

local currentMusicVolume = defaultMusicVolume
local currentEffectsVolume = defaultEffectsVolume
local currentBrightness = defaultBrightness
local currentZoom = defaultMaxZoom
local currentFov = defaultFov
local currentEffectsEnabled = true
local currentUiScale = 1

--- Arayüzün tamamını ölçeklendirir (UIScale). Mobilde de okunur kalsın diye
--- 0.8 altına inilmez.
local function applyUiScale(value: number): ()
	currentUiScale = math.clamp(value, UI_SCALE_MIN, UI_SCALE_MAX)
	local gui = UIKit.getGui()
	local scale = gui:FindFirstChild("UIKitScale")
	if scale == nil then
		scale = Instance.new("UIScale") :: UIScale
		scale.Name = "UIKitScale"
		scale.Parent = gui
	end
	scale.Scale = currentUiScale
end

local function applyMusicVolume(value: number): ()
	currentMusicVolume = math.clamp(value, VOLUME_MIN, VOLUME_MAX)
	if musicGroup ~= nil then
		musicGroup.Volume = currentMusicVolume
	end
end

local function applyEffectsVolume(value: number): ()
	currentEffectsVolume = math.clamp(value, VOLUME_MIN, VOLUME_MAX)
	if effectsGroup ~= nil then
		effectsGroup.Volume = currentEffectsVolume
	end
end

local function applyBrightness(value: number): ()
	currentBrightness = math.clamp(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX)
	Lighting.Brightness = currentBrightness
end

local function applyZoom(value: number): ()
	currentZoom = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	player.CameraMaxZoomDistance = currentZoom
	player.CameraMinZoomDistance = math.min(currentZoom, MIN_ZOOM_FLOOR)
end

local function applyFov(value: number): ()
	currentFov = math.clamp(value, FOV_MIN, FOV_MAX)
	local cam = workspace.CurrentCamera
	if cam ~= nil then
		cam.FieldOfView = currentFov
	end
end

--- Efekt kalitesi: client tarafı gölge/görüntü ayarları. Oyun override ederse etkisiz olur.
local function applyEffectsQuality(enabled: boolean): ()
	currentEffectsEnabled = enabled
	Lighting.GlobalShadows = if enabled then defaultShadows else false
end

--- Tüm ayarları yeniden uygular (yeniden doğma / kamera değişimi sonrası).
local function reapplyAll(): ()
	applyMusicVolume(currentMusicVolume)
	applyEffectsVolume(currentEffectsVolume)
	applyBrightness(currentBrightness)
	applyZoom(currentZoom)
	applyFov(currentFov)
	applyEffectsQuality(currentEffectsEnabled)
	applyUiScale(currentUiScale)
end

--[[
	Pencere
]]

local settingsWindow = UIKit.window({ Title = "AYARLAR", Name = "SettingsWindow", WidthScale = 0.86, HeightScale = 0.72 })
local settingsBody = settingsWindow.Body

local function makeSliderRow(
	parent: Instance,
	title: string,
	min: number,
	max: number,
	step: number,
	initial: number,
	format: (number) -> string,
	onChange: (number) -> ()
): any
	local label = UIKit.label(parent, "")
	local slider = UIKit.slider({
		Min = min,
		Max = max,
		Step = step,
		Value = initial,
		OnChange = function(value: number)
			label.Text = `{title}: {format(value)}`
			onChange(value)
		end,
	})
	slider.Frame.Parent = parent
	label.Text = `{title}: {format(initial)}`
	return slider
end

local function formatVolume(value: number): string
	return `{math.floor(value * 100)}%`
end

local function formatNumber(value: number): string
	return tostring(math.floor(value + 0.5))
end

local musicSlider: any = nil
local effectsSlider: any = nil
local brightnessSlider: any = nil
local zoomSlider: any = nil
local fovSlider: any = nil
local uiScaleSlider: any = nil

-- Satırlar (slider tutamaçları reset butonu tarafından kullanılır).
if musicGroup ~= nil then
	musicSlider = makeSliderRow(settingsBody, "Müzik", VOLUME_MIN, VOLUME_MAX, VOLUME_STEP, currentMusicVolume, formatVolume, applyMusicVolume)
else
	UIKit.label(settingsBody, "Müzik: SoundGroup bulunamadı (SoundService > 'Music')")
end

if effectsGroup ~= nil then
	effectsSlider = makeSliderRow(settingsBody, "Efekt sesi", VOLUME_MIN, VOLUME_MAX, VOLUME_STEP, currentEffectsVolume, formatVolume, applyEffectsVolume)
else
	UIKit.label(settingsBody, "Efekt sesi: SoundGroup bulunamadı (SoundService > 'SFX')")
end

brightnessSlider = makeSliderRow(settingsBody, "Parlaklık", BRIGHTNESS_MIN, BRIGHTNESS_MAX, BRIGHTNESS_STEP, currentBrightness, formatNumber, applyBrightness)
zoomSlider = makeSliderRow(settingsBody, "Kamera mesafesi", ZOOM_MIN, ZOOM_MAX, ZOOM_STEP, currentZoom, formatNumber, applyZoom)
fovSlider = makeSliderRow(settingsBody, "Görüş açısı (FOV)", FOV_MIN, FOV_MAX, FOV_STEP, currentFov, formatNumber, applyFov)
uiScaleSlider = makeSliderRow(settingsBody, "Arayüz ölçeği", UI_SCALE_MIN, UI_SCALE_MAX, UI_SCALE_STEP, currentUiScale, formatNumber, applyUiScale)

local effectsButton: TextButton
effectsButton = UIKit.button(settingsBody, "Efekt kalitesi: Yüksek", function()
	applyEffectsQuality(not currentEffectsEnabled)
	effectsButton.Text = if currentEffectsEnabled then "Efekt kalitesi: Yüksek" else "Efekt kalitesi: Düşük"
end)
effectsButton.Size = UDim2.new(1, 0, 0, 48)

local resetButton = UIKit.button(settingsBody, "Varsayılana dön", function()
	applyMusicVolume(defaultMusicVolume)
	applyEffectsVolume(defaultEffectsVolume)
	applyBrightness(defaultBrightness)
	applyZoom(defaultMaxZoom)
	player.CameraMinZoomDistance = defaultMinZoom
	applyFov(defaultFov)
	applyEffectsQuality(true)

	if musicSlider ~= nil then
		musicSlider:SetValue(defaultMusicVolume)
	end
	if effectsSlider ~= nil then
		effectsSlider:SetValue(defaultEffectsVolume)
	end
	if brightnessSlider ~= nil then
		brightnessSlider:SetValue(defaultBrightness)
	end
	if zoomSlider ~= nil then
		zoomSlider:SetValue(defaultMaxZoom)
	end
	if fovSlider ~= nil then
		fovSlider:SetValue(defaultFov)
	end
	applyUiScale(1)
	if uiScaleSlider ~= nil then
		uiScaleSlider:SetValue(1)
	end
	effectsButton.Text = "Efekt kalitesi: Yüksek"

	UIKit.toast("Varsayılan ayarlar geri alındı.")
end)
resetButton.Size = UDim2.new(1, 0, 0, 48)

-- Rejoin butonu: server'daki RejoinService'i tetikler.
local rejoinButton = UIKit.button(settingsBody, "Yeniden bağlan", function()
	local remote = rejoinRequest
	if remote == nil then
		UIKit.toast("Rejoin servisi bulunamadı.")
		return
	end
	remote:FireServer()
	UIKit.toast("Yeniden bağlanma isteği gönderildi.")
end)
rejoinButton.Size = UDim2.new(1, 0, 0, 48)

local note = UIKit.label(settingsBody, "Bu ayarlar sadece görünüm ve ses içindir; oyuna yetki vermez ve kaydedilmez.")
note.TextSize = 13
note.TextColor3 = Color3.fromRGB(160, 168, 185)

--[[
	Giriş düğmesi
]]

local settingsOpenButton = Instance.new("TextButton") :: TextButton
settingsOpenButton.Name = "SettingsButton"
settingsOpenButton.AnchorPoint = Vector2.new(0, 0)
settingsOpenButton.Position = UDim2.fromOffset(12, 12)
settingsOpenButton.Size = UDim2.fromOffset(84, 48)
settingsOpenButton.BackgroundColor3 = Color3.fromRGB(38, 41, 50)
settingsOpenButton.BackgroundTransparency = 0.15
settingsOpenButton.BorderSizePixel = 0
settingsOpenButton.Text = "Ayarlar"
settingsOpenButton.TextColor3 = Color3.fromRGB(240, 240, 245)
settingsOpenButton.TextSize = 15
settingsOpenButton.Font = Enum.Font.GothamBold
settingsOpenButton.Parent = UIKit.getGui()

local settingsOpenCorner = Instance.new("UICorner")
settingsOpenCorner.CornerRadius = UDim.new(0, 10)
settingsOpenCorner.Parent = settingsOpenButton

track(settingsOpenButton.Activated:Connect(function()
	settingsWindow:SetVisible(not settingsWindow:IsVisible())
end))

--[[
	Yeniden doğma / kamera değişimi
]]

track(player.CharacterAdded:Connect(function()
	task.defer(reapplyAll)
end))

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	reapplyAll()
end))

reapplyAll()

--[[
	BÖLÜM 5 — Yönetici paneli

	YÖNETİCİ PANELİ (ui_baglanti_belgesi.md §3)

	• Yetki SERVER'DA UserId ile kontrol edilir (AdminCommands modülü).
	  Buradaki UserId listesi SADECE görünürlüktür; güvenlik değildir.
	• Komut yazılmaz: hedef listeden seçilir, komutlar butonlardır,
	  hız değeri kaydırıcıdan gelir. Mobilde de kullanılabilir.
	• Sunucu her komuta `Notify` ile cevap verir. Yetkisiz denemede cevap
	  GELMEZ → 3 sn sonra "Yanıt yok (yetkin olmayabilir)" gösterilir.
	• Oyuncu hedeflemede DisplayName DEĞİL, `Player.Name` kullanılır
	  (DisplayName benzersiz değildir, server bulamaz).
	• Notify dinleyicisi TEK yerde buradadır: AbilityClient'taki eski
	  Notify bloğu SİLİNMİŞTİR (çift bildirim olmasın).

	KURULUM: aşağıdaki LOCAL_ADMIN_USER_IDS tablosuna kendi UserId'ni yaz.
	Panel, listede olmayan oyuncu için HİÇ OLUŞTURULMAZ.
]]

--[[
	GÖRÜNÜRLÜK AYARI — kendi UserId'ni buraya yaz.
	Sunucu tarafındaki ADMIN_USER_IDS ile AYNI olmalı (AdminCommands modülü).
]]

local LOCAL_ADMIN_USER_IDS: { [number]: boolean } = {
	-- [123456789] = true, -- ← KENDİ UserId'ni yaz
}

local isLocalAdmin = LOCAL_ADMIN_USER_IDS[player.UserId] == true

local function buildAdminPanel(): ()


	--[[
		Sunucu sözleşmesi (ui_baglanti_belgesi.md §1)
	]]

	local MAX_COMMAND_LENGTH = 20
	local MAX_ARGUMENT_LENGTH = 100
	local REPLY_TIMEOUT = 3

	--[[
		Durum
	]]

	local selectedTarget: string? = nil -- nil = kendin
	local awaitingReply = false
	local replyLine: TextLabel? = nil

	--[[
		Pencere
	]]

	local adminWindow = UIKit.window({ Title = "YÖNETİCİ", Name = "AdminWindow", WidthScale = 0.88, HeightScale = 0.78 })
	local adminBody = adminWindow.Body

	local resultLabel = UIKit.label(adminBody, "Sonuç: -")
	resultLabel.TextSize = 14
	resultLabel.TextColor3 = Color3.fromRGB(160, 168, 185)
	replyLine = resultLabel

	local function setResult(text: string): ()
		if replyLine ~= nil then
			replyLine.Text = `Sonuç: {text}`
		end
	end

	--[[
		Hedef listesi (Player.Name — DisplayName benzersiz değildir)
	]]

	local targetHolder = UIKit.label(adminBody, "Hedef: (yok → kendin)")
	targetHolder.TextSize = 14

	local targetButtons: { TextButton } = {}

	local function clearTargetButtons(): ()
		for _, button in targetButtons do
			button:Destroy()
		end
		targetButtons = {}
	end

	-- Kapsam daraltma: iç içe fonksiyonlarda upvalue daraltması çalışmıyor,
	-- bu yüzden non-nil kopyaları alıyoruz.
	local commandRemote = adminCommand
	local notifyRemote = notifyEvent

	if commandRemote == nil or notifyRemote == nil then
		warn("[X MENU UI] AdminCommand/Notify bulunamadı — yönetici paneli kurulmadı.")
		return
	end

	local function buildTargetButtons(): ()
		clearTargetButtons()

		local selfButton = UIKit.button(adminBody, "Kendim", function()
			selectedTarget = nil
			targetHolder.Text = "Hedef: kendin"
			buildTargetButtons()
		end)
		selfButton.Size = UDim2.new(1, 0, 0, 44)
		selfButton.LayoutOrder = 1
		table.insert(targetButtons, selfButton)

		local order = 2
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local name = other.Name
				local button = UIKit.button(adminBody, name, function()
					selectedTarget = name
					targetHolder.Text = `Hedef: {name}`
					buildTargetButtons()
				end)
				button.Size = UDim2.new(1, 0, 0, 44)
				button.LayoutOrder = order
				table.insert(targetButtons, button)
				order += 1
			end
		end
	end

	buildTargetButtons()

	--[[
		Komut gönderimi
	]]

	local function targetArgument(requireTarget: boolean): string?
		if requireTarget then
			if selectedTarget == nil then
				UIKit.toast("Önce bir oyuncu seç.")
				return nil
			end
			return selectedTarget
		end
		return selectedTarget or ""
	end

	--- Hedef zorunlu değilse asla nil dönmez ("" = kendin).
	local function optionalTarget(): string
		local target = targetArgument(false)
		if target == nil then
			return ""
		end
		return target
	end

	local function sendCommand(command: string, argument: string): ()
		if #command > MAX_COMMAND_LENGTH then
			UIKit.toast("Komut çok uzun.")
			return
		end
		if #argument > MAX_ARGUMENT_LENGTH then
			argument = string.sub(argument, 1, MAX_ARGUMENT_LENGTH)
		end

		awaitingReply = true
		setResult("bekleniyor...")
		commandRemote:FireServer(command, argument)

		-- Sunucu cevap vermezse (yetkisiz / rate limit) kullanıcı sonsuza kadar beklemesin.
		task.delay(REPLY_TIMEOUT, function()
			if awaitingReply then
				awaitingReply = false
				setResult("Yanıt yok (yetkin olmayabilir)")
				UIKit.toast("Yanıt yok (yetkin olmayabilir)")
			end
		end)
	end

	--[[
		Hız komutu: kaydırıcı (tam sayı) + uygula + sıfırla
	]]

	local speedValue = 0

	UIKit.label(adminBody, "Hız (0-100)")

	-- ÖNCE etiket, SONRA kaydırıcı: UIKit.slider oluşturulurken OnChange bir kez
	-- çağrılır; etiket oluşmadan önce çağrılırsa "nil" hatası verir.
	local speedLabel = UIKit.label(adminBody, "Hız: 0")
	local speedSlider = UIKit.slider({
		Min = 0,
		Max = 100,
		Step = 1,
		Value = 0,
		OnChange = function(value: number)
			speedValue = value
			speedLabel.Text = `Hız: {math.floor(value)}`
		end,
	})
	speedSlider.Frame.Parent = adminBody
	speedLabel.TextSize = 14
	speedLabel.LayoutOrder = 1

	local speedApplyButton = UIKit.button(adminBody, "Hızı uygula", function()
		local argument = optionalTarget()
		sendCommand("speed", `{math.floor(speedValue)} {argument}`)
	end)
	speedApplyButton.Size = UDim2.new(1, 0, 0, 44)

	local speedResetButton = UIKit.button(adminBody, "Hızı sıfırla", function()
		local argument = optionalTarget()
		sendCommand("speed", `reset {argument}`)
	end)
	speedResetButton.Size = UDim2.new(1, 0, 0, 44)

	--[[
		Diğer komutlar
	]]

	local godEnabled = false

	local godButton: TextButton
	godButton = UIKit.button(adminBody, "Tanrı modu: kapalı", function()
		godEnabled = not godEnabled
		godButton.Text = if godEnabled then "Tanrı modu: açık" else "Tanrı modu: kapalı"
		local argument = optionalTarget()
		sendCommand("god", `{if godEnabled then "on" else "off"} {argument}`)
	end)
	godButton.Size = UDim2.new(1, 0, 0, 44)

	local healButton = UIKit.button(adminBody, "İyileştir", function()
		local argument = optionalTarget()
		sendCommand("heal", argument)
	end)
	healButton.Size = UDim2.new(1, 0, 0, 44)

	local tpButton = UIKit.button(adminBody, "Oyuncuya ışınlan", function()
		local argument = targetArgument(true)
		if argument == nil then
			return
		end
		sendCommand("tp", argument)
	end)
	tpButton.Size = UDim2.new(1, 0, 0, 44)

	local bringButton = UIKit.button(adminBody, "Oyuncuyu yanıma getir", function()
		local argument = targetArgument(true)
		if argument == nil then
			return
		end
		sendCommand("bring", argument)
	end)
	bringButton.Size = UDim2.new(1, 0, 0, 44)

	--[[
		Atma: sebep yazılmaz, hazır seçeneklerden biri seçilir
	]]

	local kickReason: string? = nil
	local kickReasonLabel = UIKit.label(adminBody, "Atma sebebi: (yok)")
	kickReasonLabel.TextSize = 14

	local function setKickReason(reason: string?): ()
		kickReason = reason
		kickReasonLabel.Text = if reason == nil then "Atma sebebi: (yok)" else `Atma sebebi: {reason}`
	end

	local KICK_REASONS = { "spam yaptın", "hile kullanımı", "haksız davranış", "kurallara aykırı" }

	for _, reason in KICK_REASONS do
		local reasonButton = UIKit.button(adminBody, reason, function()
			setKickReason(reason)
		end)
		reasonButton.Size = UDim2.new(1, 0, 0, 40)
	end

	local kickButton = UIKit.button(adminBody, "Oyuncuyu at", function()
		local argument = targetArgument(true)
		if argument == nil then
			return
		end
		if kickReason ~= nil then
			argument = `{argument} {kickReason}`
		end
		sendCommand("kick", argument)
	end)
	kickButton.Size = UDim2.new(1, 0, 0, 44)

	--[[
		Giriş düğmesi (sadece yetkili görünümü olan hesaplarda görünür)
	]]

	local adminOpenButton = Instance.new("TextButton") :: TextButton
	adminOpenButton.Name = "AdminButton"
	adminOpenButton.AnchorPoint = Vector2.new(1, 0)
	adminOpenButton.Position = UDim2.new(1, -12, 0, 12)
	adminOpenButton.Size = UDim2.fromOffset(96, 48)
	adminOpenButton.BackgroundColor3 = Color3.fromRGB(64, 156, 255)
	adminOpenButton.BorderSizePixel = 0
	adminOpenButton.Text = "YÖNETİM"
	adminOpenButton.TextColor3 = Color3.fromRGB(240, 240, 245)
	adminOpenButton.TextSize = 15
	adminOpenButton.Font = Enum.Font.GothamBold
	adminOpenButton.Parent = UIKit.getGui()

	local adminOpenCorner = Instance.new("UICorner")
	adminOpenCorner.CornerRadius = UDim.new(0, 10)
	adminOpenCorner.Parent = adminOpenButton

	track(adminOpenButton.Activated:Connect(function()
		adminWindow:SetVisible(not adminWindow:IsVisible())
	end))

	--[[
		Sunucu cevabı (Notify) — tek bildirim kaynağı
	]]

	track(notifyRemote.OnClientEvent:Connect(function(message: unknown)
		if typeof(message) ~= "string" then
			return
		end

		if awaitingReply then
			awaitingReply = false
			setResult(message)
		else
			UIKit.toast(message)
		end
	end))

	--[[
		Oyuncu listesi güncellemesi
	]]

	track(Players.PlayerAdded:Connect(function()
		buildTargetButtons()
	end))

	track(Players.PlayerRemoving:Connect(function()
		buildTargetButtons()
		if selectedTarget ~= nil then
			for _, other in Players:GetPlayers() do
				if other.Name == selectedTarget then
					return
				end
			end
			selectedTarget = nil
			targetHolder.Text = "Hedef: (yok → kendin)"
			buildTargetButtons()
		end
	end))

end

if isLocalAdmin then
	buildAdminPanel()
end

-- ============================================================================
-- TEMİZLİK: script tekrar çalıştırılırsa bağlantılar kesilir, arayüz yok edilir
-- ============================================================================

sharedGlobals[REGISTRY_KEY] = {
	Cleanup = function()
		if cleanupAbilityBar ~= nil then
			pcall(cleanupAbilityBar)
			cleanupAbilityBar = nil
		end

		for _, connection in connections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(connections)

		local gui = playerGui:FindFirstChild("UIKitGui")
		if gui ~= nil then
			gui:Destroy()
		end
	end,
}

print("[X MENU UI] Hazır. Ayarlar: sol üstteki düğme. Yönetici: sağ üstteki düğme (yetkili hesap).")
