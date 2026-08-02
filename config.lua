Config = {}

-- Framework: 'qb-core' | 'qbx_core' | 'esx' | 'auto'
Config.Framework = 'auto'
Config.FrameworkResource = nil -- optional override resource name

-- Inventory: 'ox_inventory' | 'qb-inventory' | 'auto'
Config.Inventory = 'auto'
Config.QBInventoryResourceName = 'qb-inventory'
Config.ItemImagePath = 'nui://ox_inventory/web/images/'

-- Target auto-detected (ox_target / qb-target)
Config.PreferOxTarget = true

Config.OpenKey = 'F11'
Config.OpenCommand = 'criminal'
Config.Locale = 'en'

-- /zoneeditor freecam PolyZone creator
Config.ZoneEditorStartHeight = 45.0 -- how high freecam starts above the player
Config.ZoneEditorBaseSpeed = 0.65   -- freecam move speed multiplier

Config.CurrencyName = 'bitcoin'
Config.CurrencyLabel = 'Bitcoin'

Config.CanCreateOrganizations = true
Config.OrganizationCreationPrice = 500
Config.MaximumOrganizationMembers = false -- number or false
Config.TransferOwnershipWhenOwnerLeaves = true
Config.RemoveOrganizationWhenEmpty = true

Config.BlacklistedJobs = {
    police = true,
    sheriff = true,
    state = true,
}

Config.AutoCreateQBGang = {
    -- vagos = '#DE2A21',
    -- ballas = '#9D27B0',
    -- families = '#4CAF50',
}

Config.DefaultRoles = {
    {
        name = 'Leader',
        grade = 100,
        permissions = {
            canInvite = true,
            canKick = true,
            canPromote = true,
            canStartWar = true,
            canManageZones = true,
            canPlaceBounty = true,
            canManageBank = true,
            canAccessStorage = true,
            canEditLogo = true,
        },
    },
    {
        name = 'Officer',
        grade = 50,
        permissions = {
            canInvite = true,
            canKick = true,
            canPromote = false,
            canStartWar = true,
            canManageZones = true,
            canPlaceBounty = true,
            canManageBank = false,
            canAccessStorage = true,
            canEditLogo = true,
        },
    },
    {
        name = 'Member',
        grade = 1,
        permissions = {
            canInvite = false,
            canKick = false,
            canPromote = false,
            canStartWar = false,
            canManageZones = false,
            canPlaceBounty = false,
            canManageBank = false,
            canAccessStorage = true,
            canEditLogo = false,
        },
    },
}

Config.DefaultProtectionValue = 1
Config.ProtectionValuePrice = 100
Config.MaxProtectionLevel = 5

Config.DefaultNPCValue = 0
Config.NPCValuePrice = 100
Config.MaxNPCValue = 5
Config.NPCAttackOnlyWhenWar = true
Config.NPCModels = {
    'g_m_m_chicold_01',
    'csb_brucie2',
    'g_m_y_korean_02',
    'csb_vincent',
}
Config.NPCWeapons = {
    'WEAPON_PISTOL',
    'WEAPON_MICROSMG',
    'WEAPON_PUMPSHOTGUN',
}

Config.EnableGenerationWhenUnowned = true
Config.EnableProcessingWhenUnowned = true
Config.EnableSellingWhenUnowned = true
Config.HouseZoneCapture = true

Config.IsBountyStatWipe = false
Config.IsBountyInventoryWipe = false
Config.MinimalBounty = 200
Config.KillInContinentalZoneSetBounty = true
Config.BountyPriceSetOnContinentalKill = 200

Config.BaseZoneWarTime = 10 -- minutes
Config.PriceToStartWar = 0
Config.OwnedZoneAdvantage = 500
Config.WarScoreIncrease = 20 -- points/sec per alive member in the zone
Config.WarScoreDeathPenalty = 20 -- points/sec lost per dead member in the zone
Config.WarScoreFloor = 0 -- scores cannot drop below this
-- Any org can enter an active war zone and rack up their own score; highest wins
Config.AllowThirdPartyContest = true
Config.WarHudMaxTeams = 4 -- max org rows on the in-zone war HUD
Config.OrganizationCooldown = 5 -- minutes
Config.ZoneCooldown = 10 -- minutes
Config.CurrencyAward = 200
Config.MaximumOrganizationWars = 1 -- 0 = unlimited
Config.CriminalOnlineRequiredToStartWar = 1
Config.OnlyOwnerCanStartWar = false
Config.OrganizationMembersRequiredOnlineToAttackZone = 1

Config.WarRewards = {
    bandage = 2,
    lockpick = { 0, 3 },
}

-- Empty = wars allowed any time
Config.TimeWhenWarCanStart = {
    -- { beginWar = { h = 21, m = 0 }, endWar = { h = 24, m = 0 } },
    -- { beginWar = { h = 0, m = 0 }, endWar = { h = 2, m = 0 } },
}

Config.DisplayWarWall = true
Config.DisplayWallWarForEveryone = true
Config.DistanceToDisplayWall = 260.0
Config.WarWallHeight = 14.0
Config.WarWallCellSize = 1.25 -- diagonal stripe cell size
Config.WarWallAlpha = 95
Config.WarWallLogoSize = 2.6 -- meters
-- Score UI only while standing inside the contested zone
Config.WarHudOnlyInsideZone = true
Config.MaxOrgLogoLength = 512

Config.ZoneTypeTemplates = {
    weed_generation = {
        Title = 'Weed Farm',
        Type = 'generation',
        Time = 60000,
        GenerationItems = {
            { itemName = 'weed_baggy', itemAmount = 1 },
            { itemName = 'weed_ogkush', itemAmount = 1 },
        },
    },
    cocaine_processing = {
        Title = 'Cocaine Lab',
        Type = 'processing',
        Time = 60000,
        ProcessingItems = {
            {
                ProcessingFromItem = 'coca_leaf',
                ProcessingFromItemAmount = 10,
                ProcessingToItem = 'cokebaggy',
                ProcessingToItemAmount = 1,
            },
        },
    },
    drug_sales = {
        Title = 'Drug Sales Point',
        Type = 'sales',
        Time = 60000,
        SalesItems = {
            { SaleItem = 'cokebaggy', SaleAmount = 10, SalePriceForAmount = 100 },
            { SaleItem = 'meth', SaleAmount = 5, SalePriceForAmount = 150 },
        },
    },
    gang_house = {
        Title = 'Gang House',
        Type = 'house',
        Time = 0,
    },
    continental = {
        Title = 'Continental',
        Type = 'continental',
        Time = 0,
        Shop = {
            items = {
                lockpick = 10,
                armor = 50,
            },
            weapons = {
                weapon_pistol = 100,
                weapon_smg = 200,
            },
        },
    },
}

-- Example starter zones (imported on first boot if DB empty). Edit / remove freely.
Config.Zones = {
    --[[
    grove_house = {
        Title = 'Grove Street House',
        Type = 'house',
        Points = {
            vector2(-14.0, -1445.0),
            vector2(20.0, -1445.0),
            vector2(20.0, -1410.0),
            vector2(-14.0, -1410.0),
        },
        MinZ = 28.0,
        MaxZ = 40.0,
        Storages = {
            ['grove-storage01'] = {
                Coords = vector3( -10.0, -1430.0, 31.1 ),
                Prop = 'prop_box_wood02a',
                Rotation = 0.0,
                slots = 50,
                maxWeight = 2500000,
                OnlyOwnerCanAccessStorage = true,
            },
        },
    },
    ]]
}

Config.CriminalTitles = {
    [1] = {
        Title = 'Pickpocket',
        Color = '#6e6e6e',
        Require = { kills = 0 },
    },
    [2] = {
        Title = 'Thug',
        Color = '#87b5ff',
        Require = { kills = 10 },
    },
    [3] = {
        Title = 'Enforcer',
        Color = '#4caf50',
        Require = { kills = 25, wars_won = 1 },
    },
    [4] = {
        Title = 'Shot Caller',
        Color = '#ff9800',
        Require = { kills = 50, wars_won = 3, bounties = 2 },
    },
    [5] = {
        Title = 'Kingpin',
        Color = '#e53935',
        Require = { kills = 100, wars_won = 8, bounties = 5 },
    },
}

Config.Debug = false

Config.AdminGroups = {
    admin = true,
    god = true,
}
