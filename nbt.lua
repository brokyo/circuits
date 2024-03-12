-- TBD
-- Quad polyphonic tracker

-- -- Core libraries
local nb = require "nb/lib/nb"
local musicutil = require "musicutil"
local lattice = require "lattice"
local clock = require "clock"

local scale_names = {} -- A bit of a hack to get the scale names into a usable format for setting params
for i = 1, #musicutil.SCALES do
    table.insert(scale_names, musicutil.SCALES[i].name) 
end

local g = grid.connect()

local inactive_light = 1
local dim_light = 2
local medium_light = 5
local high_light = 10

local active_tracker_index = 1 -- Used to manage state on norns screen and grid

local trackers = {
    {
        voice_id = nil, 
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {1, 3}, velocity = 0.5, swing = 50, division = 1.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 0.25},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1.5},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 1},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {3}, velocity = 0.5, swing = 50, division = 2},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
        }, root_octave = 4
    },
    {
        voice_id = nil, 
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {2}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
        }, root_octave = 4
    },
    {
        voice_id = nil, 
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {3}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
        }, root_octave = 4
    },
    {
        voice_id = nil, 
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {4}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 0.5},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 0.5},
        }, root_octave = 4
    },
}

function build_scale(root_octave)
    local root_note = (root_octave * 12) + params:get("key") - 1 -- Get the MIDI note for the scale root. Adjust by 1 due to Lua indexing
    local scale = musicutil.generate_scale(root_note, params:get("mode"), 2)
 
    return scale
end

primary_lattice = lattice:new()

local sequencers = {}
for i = 1, #trackers do
    local tracker = trackers[i] -- Create an alias for convenience
    tracker.voice_id = i -- Assign an id to the tracker voice so we can manage it with n.b elsewhere
    
    sequencers[i] = primary_lattice:new_sprocket{
        action = function()
            tracker.current_position = (tracker.current_position % tracker.length) + 1 -- Increase the tracker position (step) at the end of the call. Loop through if it croses the length.

            local current_step = tracker.steps[tracker.current_position] -- Get the table at the current step to configure play event

            local degree_table = tracker.steps[tracker.current_position].degrees -- Get the table of degrees to play for this step
            local scale_notes = build_scale(tracker.root_octave) -- Generate a scale based on global key and mode
            
            sequencers[i]:set_division(current_step.division) -- Set the division for the current step
            sequencers[i]:set_swing(current_step.swing) -- Set the swing for the current step

            if #degree_table > 0 then -- Check to see if the degree table at the current step contains values
                for _, degree in ipairs(degree_table) do  -- If it does is, iterate through each degree
                    local note = scale_notes[degree] -- And match it to the appropriate note in the scale
                    local player = params:lookup_param("voice_" .. i):get_player() -- Get the n.b voice
                    player:play_note(note, current_step.velocity, 1) -- And play the note
                end
            end
            grid_redraw()
        end,
        division = 1
    }
end

function init()
    
    params:add{
        type = "option",
        id = "key",
        name = "Key",
        options = musicutil.NOTE_NAMES,
        default = 3
      }
      
      params:add{
        type = "option",
        id = "mode",
        name = "Mode",
        options = scale_names,
        default = 5,
      }

    nb:init()
    for i = 1, #trackers do
        nb:add_param("voice_" .. i, "voice_" .. i)
    end
    nb:add_player_params()

    primary_lattice:start()
    grid_redraw()

end

-- Constants to separate the control panel
local CONTROL_COLUMNS_START = 13
local CONTROL_COLUMNS_END = 16
local TRACKER_SELECTION_ROW = 8
local LENGTH_SELECTION_START_ROW = 5
local LENGTH_SELECTION_END_ROW = 7

-- Function to change the active tracker
function changeActiveTracker(trackerIndex)
    active_tracker_index = trackerIndex
    grid_redraw()
    redraw()
end

-- Function to update the length of the active tracker (i.e the number of steps that will play of the possible 12)
function updateTrackerLength(x, y)
    local lengthOffset = (y - LENGTH_SELECTION_START_ROW) * 4 + (x - CONTROL_COLUMNS_START + 1)
    trackers[active_tracker_index].length = lengthOffset
    grid_redraw()
end

-- Logic for handling key pressed on the control panel
function handleControlColumnPress(x, y, pressed)
    if not pressed then return end -- Ignore key releases

    if y == TRACKER_SELECTION_ROW then
        changeActiveTracker(x - CONTROL_COLUMNS_START + 1)
    elseif y >= LENGTH_SELECTION_START_ROW and y <= LENGTH_SELECTION_END_ROW then
        updateTrackerLength(x, y)
    end
    -- LATER: Maybe velocity, swing, and division are set here. Maybe that's just handled on the norns screen. Dunno.
end

function g.key(x, y, pressed)
    if x >= CONTROL_COLUMNS_START and x <= CONTROL_COLUMNS_END then -- Catch key presses in the control panel and handle them with distinct logic
        handleControlColumnPress(x, y, pressed)
    else -- Otherwise treat them as edits to the tracker (LATER: Break this logic out as well)
        local degree = 9 - y -- Invert the y-coordinate to match the horizontal layout
        local working_tracker = trackers[active_tracker_index]

        if pressed == 1 and x <= 12 then -- When a degree is pressed and the associated step is less than the max sequence length
            local index = nil
            for i, v in ipairs(working_tracker.steps[x].degrees) do
                if v == degree then
                    index = i
                    break
                end
            end
            if index then -- If it is, remove it
                table.remove(working_tracker.steps[x].degrees, index)
                print("Degree " .. degree .. " removed from step " .. x)
            else -- If it is not, add it
                table.insert(working_tracker.steps[x].degrees, degree)
                print("Degree " .. degree .. " added to step " .. x)
            end
            grid_redraw()
        end
    end
end

function enc(n, d)
    if n == 1 then
        active_tracker_index =  util.clamp(active_tracker_index + d, 1, #trackers)
        grid_redraw()
        redraw()
    end
end

function redraw()
    screen.clear()
    screen.move(64, 32)
    screen.text_center(active_tracker_index)
    screen.update()
end

function grid_redraw()
    if not g then
        print("no grid found")
        return
    end

    local working_tracker = trackers[active_tracker_index]    

    g:all(0) -- Zero out grid

    -- Draw Tracker
    for step = 1, 12 do -- Iterate through each step
        for degree = 1, 8 do -- Iterate through each degree in the step
            local grid_y = 9 - degree -- Invert the y-coordinate
            local active_degrees = working_tracker.steps[step].degrees -- Grab the table of degrees in the step
            local is_active_degree = false -- Flag to identify correct illumination level 

            -- Check if the current degree is among the active degrees for this step
            for _, active_degree in ipairs(active_degrees or {}) do
                if active_degree == degree then
                    is_active_degree = true
                    break
                end
            end

            -- Determine the light intensity based on the current step, position, and if the degree is active
            if step == working_tracker.current_position then
                if is_active_degree then
                    g:led(step, grid_y, high_light) -- Light it brightly for active degrees at the current position
                else
                    g:led(step, grid_y, dim_light) -- Light it dimly for inactive degrees at the current position
                end
            elseif is_active_degree then
                if step > working_tracker.length then
                    g:led(step, grid_y, inactive_light) -- Light it at inactive_light for active degrees in steps beyond the tracker length
                else
                    g:led(step, grid_y, medium_light) -- Light it medium for active degrees not at the current position
                end
            end
        end
    end

    -- Highlight the length of the active tracker
    for y = LENGTH_SELECTION_START_ROW, LENGTH_SELECTION_END_ROW do
        for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
            local lengthValue = (y - LENGTH_SELECTION_START_ROW) * 4 + (x - CONTROL_COLUMNS_START + 1)
            if lengthValue <= trackers[active_tracker_index].length then
                g:led(x, y, 3)
            else
                g:led(x, y, 1)
            end
        end
    end

    -- Highlight the active tracker in the control panel
    for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
        local trackerIndex = x - CONTROL_COLUMNS_START + 1
        if trackerIndex == active_tracker_index then
            g:led(x, TRACKER_SELECTION_ROW, medium_light) -- Light the active tracker at medium_light intensity
        else
            g:led(x, TRACKER_SELECTION_ROW, 0) -- Other trackers remain at inactive_light intensity
        end
    end

    g:refresh() -- Send the LED buffer to the grid
end
