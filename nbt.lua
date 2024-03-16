-- TBD
-- Quad polyphonic tracker

-- -- Core libraries
local nb = require "nb/lib/nb"
local musicutil = require "musicutil"
local lattice = require "lattice"

local scale_names = {} -- A bit of a hack to get the scale names into a usable format for setting params
for i = 1, #musicutil.SCALES do
    table.insert(scale_names, musicutil.SCALES[i].name) 
end

local g = grid.connect()

local inactive_light = 1
local dim_light = 2
local medium_light = 5
local high_light = 10

function index_of(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return nil -- Return nil if the value is not found
end

local active_tracker_index = 1 -- Used to manage state on norns screen and grid

local trackers = {
    {
        voice_id = nil, 
        playing = false,
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {1, 3}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {3}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 1/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 1/3}
        }, 
        root_octave = 4
    },
    {
        voice_id = nil, 
        playing = false,
        current_position = 0, 
        length = 8, 
        steps = {
            {degrees = {1, 3}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1, 4}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {2, 6}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {2, 7}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {3}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {8}, velocity = 0.5, swing = 50, division = 2/3},
            {degrees = {1}, velocity = 0.5, swing = 50, division = 2/3},
        }, 
        root_octave = 4 
    },
    {
        voice_id = nil, 
        playing = false,
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
        }, 
        root_octave = 4
    },
    {
        voice_id = nil, 
        playing = false,
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
        }, 
        root_octave = 4
    }
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
            if tracker.playing then -- Check if the tracker is playing
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
            end
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
local PLAYBACK_STATUS_ROW = 7
local LENGTH_SELECTION_START_ROW = 1
local LENGTH_SELECTION_END_ROW = 3

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
    if pressed == 0 then return end -- Ignore key releases

    if y == TRACKER_SELECTION_ROW then
        changeActiveTracker(x - CONTROL_COLUMNS_START + 1)
    elseif y >= LENGTH_SELECTION_START_ROW and y <= LENGTH_SELECTION_END_ROW then
        updateTrackerLength(x, y)
    elseif y == PLAYBACK_STATUS_ROW then
        -- Toggle the playing state for the tracker corresponding to the pressed key
        local trackerIndex = x - CONTROL_COLUMNS_START + 1
        if trackerIndex >= 1 and trackerIndex <= #trackers then
            trackers[trackerIndex].playing = not trackers[trackerIndex].playing
            -- Reset the current position if we stop the tracker
            if not trackers[trackerIndex].playing then
                trackers[trackerIndex].current_position = 0
            end
            grid_redraw()
        end
    end
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


function toggle_playback()
    local active_tracker = trackers[active_tracker_index]
    active_tracker.playing = not active_tracker.playing
    if not active_tracker.playing then
        active_tracker.current_position = 0
    end

    redraw()
    grid_redraw()
end

local active_section = "loop" -- Vairable to identify and control the active section of the screen
local selected_step = 1 -- Individual step to edit
local loop_selected_param = 1 -- Index to navigate between parameters in the loop section
local step_selected_param = 1 -- Index to navigate between parameters in the step section

local division_options = {1/16, 1/8, 1/4, 1/3, 1/2, 2/3, 1, 2, 4} -- Possible step divisions
local division_option_names = {"1/16", "1/8", "1/4", "1/3", "1/2", "2/3", "1", "2", "4"} -- Names as strings for showing in param list

function key(n, z)
    if n == 2 and z == 1 then -- K2 switches to Loop section
        active_section = "loop"
        redraw()
    elseif n == 3 and z == 1 then -- K3 switches to Step section 
        active_section = "step"
        redraw()
    end
end


function enc(n, d)
    if active_section == "loop" then
        if n == 2 then -- E2 navigates between parameters in the Loop section
            loop_selected_param = util.clamp(loop_selected_param + d, 1, 2) -- Three parameters: play state, octave, length
            redraw()
        elseif n == 3 then -- E3 modifies the selected parameter
            if loop_selected_param == 1 then -- Change root octave
                trackers[active_tracker_index].root_octave = util.clamp(trackers[active_tracker_index].root_octave + d, 1, 8)
                redraw()
            elseif loop_selected_param == 2 then -- Change loop length
                -- TODO: adapt to 24 steps
                trackers[active_tracker_index].length = util.clamp(trackers[active_tracker_index].length + d, 1, 12)
                redraw()
            end
        end
    elseif active_section == "step" then
        if n == 2 then -- E2 to select parameter to edit
            step_selected_param = util.clamp(step_selected_param + d, 1, 4)
            redraw()
        elseif n == 3 then -- E3 to modify the selected parameter
            local step = trackers[active_tracker_index].steps[selected_step]
            if step_selected_param == 1 then -- Navigate between steps
                selected_step = util.clamp(selected_step + d, 1, #trackers[active_tracker_index].steps)
            elseif step_selected_param == 2 then -- Modify velocity
                step.velocity = util.clamp(step.velocity + d*0.01, 0, 1) -- Increment by 0.01 for finer control
            elseif step_selected_param == 3 then -- Modify swing
                step.swing = util.clamp(step.swing + d, 0, 100)
            elseif step_selected_param == 4 then -- Modify division
                local current_division_index = index_of(division_options, step.division)
                local new_division_index = util.clamp(current_division_index + d, 1, #division_options)
                step.division = division_options[new_division_index]
            end
            redraw()
        end
    end
end

function redraw()
    screen.clear()

    -- Mode Selector
    -- Loop Edit
    screen.rect(1, 54, 60, 10)    
    if active_section == "loop" then
        screen.level(6)
    else
        screen.level(1)
    end
    screen.stroke()
    screen.move(32, 61)
    screen.text_center("Loop (k2)")

    -- Step Edit
    screen.rect(67, 54, 60, 10)
    if active_section == "step" then
        screen.level(6)
    else
        screen.level(1)
    end
    screen.stroke()
    screen.move(96, 61)
    screen.text_center("Step (k3)")

    if active_section == "loop" then
        local param_names = {"Octave", "Length"}
        local param_values = {
            tostring(trackers[active_tracker_index].root_octave),
            tostring(trackers[active_tracker_index].length)
        }
        
        for i, param in ipairs(param_names) do
            screen.level(i == loop_selected_param and 15 or 5) -- Highlight the active parameter
            screen.move(2, 10 + (i * 10))
            screen.text(param .. ": " .. param_values[i])
        end
    elseif active_section == "step" then
        -- Draw parameters for the selected step
        local step = trackers[active_tracker_index].steps[selected_step]
        local param_names = {"Step", "Velocity", "Swing", "Division"}
        local param_values = {tostring(selected_step), tostring(step.velocity), tostring(step.swing), division_option_names[index_of(division_options, step.division)]}

        for i, param in ipairs(param_names) do
            screen.level(i == step_selected_param and 15 or 5) -- Highlight the active parameter
            screen.move(2, 0 + (i * 10))
            screen.text(param .. ": " .. param_values[i])
        end
    end
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

    -- Display playback status for each tracker on row 7
    for i = 1, #trackers do
        local playbackLight = trackers[i].playing and high_light or inactive_light
        g:led(CONTROL_COLUMNS_START + i - 1, PLAYBACK_STATUS_ROW, playbackLight)
    end

    g:refresh() -- Send the LED buffer to the grid
end
