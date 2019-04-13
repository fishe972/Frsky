local VALUE = 0
local COMBO = 1

local COLUMN_2 = 150

local edit = false
local page = 1
local current = 1
local refreshState = 0
local refreshIndex = 0
local calibrationState = 0
local pageOffset = 0
local calibrationStep = 0
local pages = {}
local fields = {}
local modifications = {}
local aux1Enable = 0
local aux2Enable = 0

local configFields = {
  {"Wing type:", COMBO, 0x80, nil, { "Normal", "Delta", "VTail" } },
  {"Mounting type:", COMBO, 0x81, nil, { "Horz", "Horz rev.", "Vert", "Vert rev." } },
}

local settingsFields = {
  {"S6R functions:", COMBO, 0x9C, nil, { "Disable", "Enable" } },
  {"AUX1 select:", COMBO, 0xA8, nil, { "Disable", "Enable" } },
  {"AUX2 select:", COMBO, 0xA9, nil, { "Disable", "Enable" } },
  {"AIL direction:", COMBO, 0x82, nil, { "Normal", "Invers" }, { 255, 0 } },
  {"ELE direction:", COMBO, 0x83, nil, { "Normal", "Invers" }, { 255, 0 } },
  {"RUD direction:", COMBO, 0x84, nil, { "Normal", "Invers" }, { 255, 0 } },
  {"AIL2 direction:", COMBO, 0x9A, nil, { "Normal", "Invers" }, { 255, 0 } },
  {"ELE2 direction:", COMBO, 0x9B, nil, { "Normal", "Invers" }, { 255, 0 } },
  {"AIL stabilize gain:", VALUE, 0x85, nil, 0, 200, "%"},
  {"ELE stabilize gain:", VALUE, 0x86, nil, 0, 200, "%"},
  {"RUD stabilize gain:", VALUE, 0x87, nil, 0, 200, "%"},
  {"AIL auto level gain:", VALUE, 0x88, nil, 0, 200, "%"},
  {"ELE auto level gain:", VALUE, 0x89, nil, 0, 200, "%"},
  {"ELE upright gain:", VALUE, 0x8C, nil, 0, 200, "%"},
  {"RUD upright gain:", VALUE, 0x8D, nil, 0, 200, "%"},
  {"AIL crab gain:", VALUE, 0x8E, nil, 0, 200, "%"},
  {"RUD crab gain:", VALUE, 0x90, nil, 0, 200, "%"},
  {"AIL auto angle offset:", VALUE, 0x91, nil, -20, 20, "%", 0x6C},
  {"ELE auto angle offset:", VALUE, 0x92, nil, -20, 20, "%", 0x6C},
  {"ELE upright angle offset:", VALUE, 0x95, nil, -20, 20, "%", 0x6C},
  {"RUD upright angle offset:", VALUE, 0x96, nil, -20, 20, "%", 0x6C},
  {"AIL crab angle offset:", VALUE, 0x97, nil, -20, 20, "%", 0x6C},
  {"RUD crab angle offset:", VALUE, 0x99, nil, -20, 20, "%", 0x6C},
}

local calibrationFields = {
  {"X:", VALUE, 0x9E, 0, -100, 100, "%"},
  {"Y:", VALUE, 0x9F, 0, -100, 100, "%"},
  {"Z:", VALUE, 0xA0, 0, -100, 100, "%"}
}

-- Change display attribute to current field
local function addField(step)
  local field = fields[current]
  local min, max
  if field[2] == VALUE then
    min = field[5]
    max = field[6]
  elseif field[2] == COMBO then
    min = 0
    max = #(field[5]) - 1
  end
  if (step < 0 and field[4] > min) or (step > 0 and field[4] < max) then
    field[4] = field[4] + step
  end
end

-- Select the next or previous page
local function selectPage(step)
  page = 1 + ((page + step - 1 + #pages) % #pages)
  refreshIndex = 0
  calibrationStep = 0
  pageOffset = 0
end

-- Select the next or previous editable field
local function selectField(step)
  current = 1 + ((current + step - 1 + #fields) % #fields)
  if current > 7 + pageOffset then
    pageOffset = current - 7
  elseif current <= pageOffset then
    pageOffset = current - 1
  end
end

local function drawProgressBar()
  local width = (140 * refreshIndex) / #fields
  lcd.drawRectangle(30, 1, 144, 6)
  lcd.drawFilledRectangle(32, 3, width, 2);
end

-- Redraw the current page
local function redrawFieldsPage()
  lcd.clear()
  lcd.drawScreenTitle("S6R", page, #pages)

  if refreshIndex < #fields then
    drawProgressBar()
  end

  for index = 1, 7, 1 do
    local field = fields[pageOffset+index]
    if field == nil then
      break
    end

    local attr = current == (pageOffset+index) and ((edit == true and BLINK or 0) + INVERS) or 0

    lcd.drawText(0, 1+8*index, field[1])

    if field[4] == nil then
      lcd.drawText(COLUMN_2, 1+8*index, "---", attr)
    else
      if field[2] == VALUE then
        lcd.drawNumber(COLUMN_2, 1+8*index, field[4], LEFT + attr)
      elseif field[2] == COMBO then
        if field[4] >= 0 and field[4] < #(field[5]) then
          lcd.drawText(COLUMN_2, 1+8*index, field[5][1+field[4]], attr)
        end
      end
    end
  end
end

local function telemetryRead(field)
  return sportTelemetryPush(0x1B, 0x30, 0x0C30, field)
end

local function telemetryWrite(field, value)
  return sportTelemetryPush(0x1B, 0x31, 0x0C30, field + value*256)
end

local telemetryPopTimeout = 0
local function refreshNext()
  if refreshState == 0 then
    if calibrationState == 1 then
      if telemetryWrite(0x9D, calibrationStep) == true then
        refreshState = 1
        calibrationState = 2
        telemetryPopTimeout = getTime() + 80 -- normal delay is 500ms
      end
    elseif #modifications > 0 then
      telemetryWrite(modifications[1][1], modifications[1][2])
      modifications[1] = nil
    elseif refreshIndex < #fields then
      local field = fields[refreshIndex + 1]
      if telemetryRead(field[3]) == true then
        refreshState = 1
        telemetryPopTimeout = getTime() + 80 -- normal delay is 500ms
      end
    end
  elseif refreshState == 1 then
    local physicalId, primId, dataId, value = sportTelemetryPop()
    if physicalId == 0x1A and primId == 0x32 and dataId == 0x0C30 then
      local fieldId = value % 256
      if calibrationState == 2 then
        if fieldId == 0x9D then
          refreshState = 0
          calibrationState = 0
          calibrationStep = (calibrationStep + 1) % 6
        end
      else
        local field = fields[refreshIndex + 1]
        if fieldId == field[3] then
          local value = math.floor(value / 256)
          if field[3] >= 0x9E and field[3] <= 0xA0 then
            local b1 = value % 256
            local b2 = math.floor(value / 256)
            value = b1*256 + b2
            value = value - bit32.band(value, 0x8000) * 2
          end
          if field[2] == COMBO and #field == 6 then
            for index = 1, #(field[6]), 1 do
              if value == field[6][index] then
                value = index - 1
                break
              end
            end
          elseif field[2] == VALUE and #field == 8 then
            value = value - field[8] + field[5]
          end
          fields[refreshIndex + 1][4] = value
          refreshIndex = refreshIndex + 1
          refreshState = 0
        end
      end
    elseif getTime() > telemetryPopTimeout then
      refreshState = 0
      calibrationState = 0
    end
  end
end

local function updateField(field)
  local value = field[4]
  if field[2] == COMBO and #field == 6 then
    value = field[6][1+value]
  elseif field[2] == VALUE and #field == 8 then
    value = value + field[8] - field[5]
  end
  modifications[#modifications+1] = { field[3], value }
end

-- Main
local function runFieldsPage(event)
  if event == EVT_EXIT_BREAK then             -- exit script
    return 2
  elseif event == EVT_ENTER_BREAK then        -- toggle editing/selecting current field
    if fields[current][4] ~= nil then
      edit = not edit
      if edit == false then
        updateField(fields[current])
      end
    end
  elseif edit then
    if event == EVT_PLUS_FIRST or event == EVT_PLUS_REPT then
      addField(1)
    elseif event == EVT_MINUS_FIRST or event == EVT_MINUS_REPT then
      addField(-1)
    end
  else
    if event == EVT_MINUS_FIRST then
      selectField(1)
    elseif event == EVT_PLUS_FIRST then
      selectField(-1)
    end
  end
  redrawFieldsPage()
  return 0
end

local wingBitmaps = { "plane.bmp", "delta.bmp", "vtail.bmp" }
local mountBitmaps = { "horz.bmp", "horz-r.bmp", "vert.bmp", "vert-r.bmp" }

local function runConfigPage(event)
  fields = configFields
  local result = runFieldsPage(event)
  if fields[1][4] ~= nil then
    lcd.drawPixmap(20, 28, wingBitmaps[1 + fields[1][4]])
  end
  if fields[2][4] ~= nil then
    lcd.drawPixmap(128, 28, mountBitmaps[1 + fields[2][4]])
  end  
  return result
end

local function runSettingsPage(event)
  fields = settingsFields
  return runFieldsPage(event)
end

local calibrationPositions = { "up", "down", "left", "right", "forward", "back" }

local function runCalibrationPage(event)
  fields = calibrationFields
  if refreshIndex == #fields then
    refreshIndex = 0
  end
  lcd.clear()
  lcd.drawScreenTitle("S6R", page, #pages)
  local position = calibrationPositions[1 + calibrationStep]
  lcd.drawText(0, 9, "Turn the S6R " .. position, 0)
  lcd.drawPixmap(10, 19, position .. ".bmp")
  for index = 1, 3, 1 do
    local field = fields[index]
    lcd.drawText(80, 12+10*index, field[1], 0)
    lcd.drawNumber(90, 12+10*index, field[4]/10, LEFT+PREC2)
  end

  local attr = calibrationState == 0 and INVERS or 0
  lcd.drawText(0, 56, "Press [Enter] when ready", attr)
  if event == EVT_ENTER_BREAK then
    calibrationState = 1
  elseif event == EVT_EXIT_BREAK then
    if calibrationStep > 0 then
      calibrationStep = 0
    else
      return 2
    end
  end  
  return 0
end

-- Init
local function init()
  current, edit, refreshState, refreshIndex = 1, false, 0, 0
  pages = {
    runConfigPage,
    runSettingsPage,
    runCalibrationPage
  }
end

-- Main
local function run(event)
  if event == nil then
    error("Cannot be run as a model script!")
    return 2
  elseif event == EVT_PAGE_BREAK then
    selectPage(1)
  elseif event == EVT_PAGE_LONG then
    killEvents(event);
    selectPage(-1)
  end

  local result = pages[page](event)
  refreshNext()

  return result
end

return { init=init, run=run }