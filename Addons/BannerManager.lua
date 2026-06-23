--[[
    BannerManager - Raron Hub Addon
    ดาวน์โหลดภาพ Banner จาก URL และแสดงใน Fluent Window
    รองรับ executor ที่มี getcustomasset / getsynasset / writefile
]]

local BannerManager = {} do
    BannerManager.Library = nil
    BannerManager.BannerFrame = nil
    BannerManager.BannerHeight = 0

    -- ตั้งค่า Library (เรียกใช้ก่อน LoadBanner)
    function BannerManager:SetLibrary(Library)
        self.Library = Library
    end

    -- ฟังก์ชัน detect executor custom asset method
    local function getCustomAssetFunc()
        if getcustomasset then
            return getcustomasset
        elseif getsynasset then
            return getsynasset
        elseif isourclosure then
            -- some executors
            return getcustomasset
        end
        return nil
    end

    -- ฟังก์ชันเขียนไฟล์ (รองรับหลาย executor)
    local function safeWriteFile(name, data)
        local ok = pcall(function()
            writefile(name, data)
        end)
        return ok
    end

    --[[
        BannerManager:LoadBanner(Config)

        Config = {
            Url          = "https://...",  -- URL รูปภาพ (png/jpg)
            Height       = 80,             -- ความสูงของ banner (pixels)
            FileName     = "banner.png",   -- ชื่อไฟล์ที่บันทึก (optional)
            Transparency = 0,              -- ความโปร่งใส 0-1 (optional)
            ScaleType    = "Crop",         -- Crop / Fit / Stretch (optional)
        }
    ]]
    function BannerManager:LoadBanner(Config)
        local Library = self.Library
        assert(Library, "BannerManager: ต้องเรียก SetLibrary() ก่อน")
        assert(Library.Window, "BannerManager: Window ยังไม่ถูกสร้าง")
        assert(Config and Config.Url, "BannerManager: ต้องใส่ Url ใน Config")

        local url          = Config.Url
        local height       = Config.Height or 80
        local fileName     = Config.FileName or "raron_banner.png"
        local transparency = Config.Transparency or 0
        local scaleType    = Config.ScaleType or "Crop"

        -- 1. ดาวน์โหลดภาพ
        local rawData
        local dlOk, dlErr = pcall(function()
            rawData = game:HttpGet(url, true)
        end)

        if not dlOk or not rawData or rawData == "" then
            Library:Notify({
                Title = "BannerManager",
                Content = "ดาวน์โหลด Banner ไม่สำเร็จ",
                SubContent = tostring(dlErr),
                Duration = 6,
            })
            return false
        end

        -- 2. บันทึกไฟล์ลงใน workspace ของ executor
        local writeOk = safeWriteFile(fileName, rawData)
        if not writeOk then
            Library:Notify({
                Title = "BannerManager",
                Content = "บันทึกไฟล์ไม่สำเร็จ",
                SubContent = "Executor อาจไม่รองรับ writefile()",
                Duration = 6,
            })
            return false
        end

        -- 3. แปลงไฟล์เป็น rbxasset URL
        local customAsset = getCustomAssetFunc()
        if not customAsset then
            Library:Notify({
                Title = "BannerManager",
                Content = "Executor ไม่รองรับ getcustomasset()",
                SubContent = "ลอง executor อื่น เช่น Synapse / Krnl",
                Duration = 8,
            })
            return false
        end

        local assetUrl
        local assetOk = pcall(function()
            assetUrl = customAsset(fileName)
        end)

        if not assetOk or not assetUrl then
            Library:Notify({
                Title = "BannerManager",
                Content = "โหลด custom asset ไม่สำเร็จ",
                Duration = 6,
            })
            return false
        end

        -- 4. สร้าง Banner UI ใน Window
        local Window = Library.Window
        local Root   = Window.Root
        local TabWidth = Window.TabWidth or 160

        -- ลบ Banner เก่า (ถ้ามี)
        if self.BannerFrame then
            pcall(function() self.BannerFrame:Destroy() end)
            self.BannerFrame = nil
        end

        -- สร้าง BannerFrame วางทันทีใต้ TitleBar (y = 42)
        local BannerFrame = Instance.new("Frame")
        BannerFrame.Name = "RaronBanner"
        BannerFrame.Size = UDim2.new(1, 0, 0, height)
        BannerFrame.Position = UDim2.fromOffset(0, 42)
        BannerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        BannerFrame.BackgroundTransparency = 1
        BannerFrame.ZIndex = 3
        BannerFrame.ClipsDescendants = true
        BannerFrame.Parent = Root

        -- Image
        local BannerImage = Instance.new("ImageLabel")
        BannerImage.Image = assetUrl
        BannerImage.Size = UDim2.fromScale(1, 1)
        BannerImage.ScaleType = Enum.ScaleType[scaleType] or Enum.ScaleType.Crop
        BannerImage.BackgroundTransparency = 1
        BannerImage.ImageTransparency = transparency
        BannerImage.ZIndex = 3
        BannerImage.Parent = BannerFrame

        -- Rounded corners
        local UICorner = Instance.new("UICorner")
        UICorner.CornerRadius = UDim.new(0, 0) -- ไม่โค้งขอบ เพราะ Banner เต็มความกว้าง
        UICorner.Parent = BannerImage

        -- Gradient overlay ด้านล่าง (ทำให้กลืนกับ content)
        local Gradient = Instance.new("Frame")
        Gradient.Size = UDim2.new(1, 0, 0.4, 0)
        Gradient.Position = UDim2.new(0, 0, 0.6, 0)
        Gradient.BackgroundColor3 = Color3.fromRGB(8, 14, 28)
        Gradient.BackgroundTransparency = 0
        Gradient.BorderSizePixel = 0
        Gradient.ZIndex = 4
        Gradient.Parent = BannerFrame

        local GradientUI = Instance.new("UIGradient")
        GradientUI.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        GradientUI.Rotation = 90
        GradientUI.Parent = Gradient

        self.BannerFrame   = BannerFrame
        self.BannerHeight  = height

        -- 5. เลื่อน TabFrame และ ContainerCanvas ลงให้รองรับ banner
        -- TabFrame = Window.TabHolder.Parent
        local TabFrame = Window.TabHolder.Parent
        if TabFrame then
            TabFrame.Position = UDim2.new(0, 12, 0, 54 + height)
            TabFrame.Size     = UDim2.new(0, TabWidth, 1, -66 - height)
        end

        -- TabDisplay (ชื่อ Tab ปัจจุบัน)
        if Window.TabDisplay then
            Window.TabDisplay.Position = UDim2.fromOffset(TabWidth + 26, 56 + height)
        end

        -- ContainerCanvas (พื้นที่ content)
        if Window.ContainerCanvas then
            Window.ContainerCanvas.Size     = UDim2.new(1, -TabWidth - 32, 1, -102 - height)
            Window.ContainerCanvas.Position = UDim2.fromOffset(TabWidth + 26, 90 + height)
        end

        Library:Notify({
            Title = "BannerManager",
            Content = "โหลด Banner สำเร็จ!",
            Duration = 3,
        })

        return true
    end

    -- ลบ Banner ออก (คืน layout กลับ)
    function BannerManager:RemoveBanner()
        local Library = self.Library
        if not Library or not Library.Window then return end

        if self.BannerFrame then
            pcall(function() self.BannerFrame:Destroy() end)
            self.BannerFrame = nil
        end

        local height   = self.BannerHeight or 0
        local Window   = Library.Window
        local TabWidth = Window.TabWidth or 160

        local TabFrame = Window.TabHolder and Window.TabHolder.Parent
        if TabFrame then
            TabFrame.Position = UDim2.new(0, 12, 0, 54)
            TabFrame.Size     = UDim2.new(0, TabWidth, 1, -66)
        end

        if Window.TabDisplay then
            Window.TabDisplay.Position = UDim2.fromOffset(TabWidth + 26, 56)
        end

        if Window.ContainerCanvas then
            Window.ContainerCanvas.Size     = UDim2.new(1, -TabWidth - 32, 1, -102)
            Window.ContainerCanvas.Position = UDim2.fromOffset(TabWidth + 26, 90)
        end

        self.BannerHeight = 0
    end
end

return BannerManager
