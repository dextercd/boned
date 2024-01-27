local nxml = dofile("nxml.lua")
local translations = dofile("translations.lua")

---@param g string
---@return string[]
function glob(g)
    local dir_it
    local prepend = ""
    if jit.os == 'Windows' then
        dir_it = io.popen("dir /b " .. g)
        prepend = g:match([=[^[^/\]*[/\]]=])
    else
        dir_it = io.popen("sh -c 'ls -1 " .. g .. "'")
    end

    if not dir_it then
        error("Couldn't get list of .xml files")
    end


    local file_names = {}
    for file in dir_it:lines() do
        table.insert(file_names, prepend .. file)
    end

    dir_it:close()
    return file_names
end

---@param file_name string
---@return string
function read_entire_file(file_name)
    local handle = io.open(file_name, "rb")
    if not handle then
        error("Couldn't open file " .. file_name)
    end

    local content = handle:read("*a")
    handle:close()

    return content
end

---@param file_name string
---@param content string
function overwrite_file(file_name, content)
    local handle = io.open(file_name, "wb")
    if not handle then
        error("Could not open " .. file_name .. " for writing")
    end

    handle:write(content)
    handle:close()
end

function find_component(xml, component_type)
    for child in xml:each_child() do
        if child.name == component_type then
            return child
        end

        if child.name == "Base" then
            local in_base = find_component(child, component_type)
            if in_base then
                return in_base
            end
        end
    end
end

function try_translate(key)
    if key:sub(1, 1) ~= "$" then
        return key
    end

    return translations[key:sub(2)] or key
end

function get_wand_build_key(xml)
    local parts = {}

    for child in xml:each_child() do
        local action_comp = find_component(child, "ItemActionComponent")
        if not action_comp then
            goto continue
        end

        local spell_text = action_comp.attr.action_id
        local item_comp = find_component(child, "ItemComponent")
        if item_comp.attr.permanently_attached == "1" then
            spell_text = "AC:" .. spell_text
        end

        table.insert(parts, spell_text)

        ::continue::
    end

    return table.concat(parts, ", ")
end

function add_username(wand_xml, username)
    local item_comp = find_component(wand_xml, "ItemComponent")
    if not item_comp then
        error("No item component..?")
    end

    -- We store the original name in the wand and check it first so the script
    -- is idempotent
    local original_name = item_comp.attr.original_name
    if
        original_name == nil and
        item_comp.attr.item_name ~= nil and
        item_comp.attr.item_name ~= "" and
        item_comp.attr.item_name ~= "default_gun"
    then
        original_name = item_comp.attr.item_name
    end

    if original_name == nil then
        original_name = "Wand"
    end

    item_comp.attr.original_name = original_name
    item_comp.attr.always_use_item_name_in_ui = "1"

    local new_name = username .. ": " .. try_translate(original_name)
    item_comp.attr.item_name = new_name

    -- Just to be sure, but I don't think this field is used anywhere
    local ability_component = find_component(wand_xml, "AbilityComponent")
    if ability_component then
        ability_component.attr.ui_name = new_name
    end
end

local seen_builds = {}

for _, arg in ipairs(arg) do
    local xml_files
    if arg:match('%.xml$') then
        xml_files = {arg}
    else
        -- Assume it's a folder
        if not arg:sub(-1, -1):match("[/\\]") then
            arg = arg .. "/"
        end
        xml_files = glob(arg .. "*.xml")
    end
    for _, xml_file_name in ipairs(xml_files) do
        print("Processing: " .. xml_file_name)
        local username = xml_file_name:match([[([^/\]*)%.xml]])
        local wand_xml = nxml.parse(read_entire_file(xml_file_name))

        add_username(wand_xml, username)
        overwrite_file(xml_file_name, nxml.tostring(wand_xml, false, "    "))

        local wand_build_key = get_wand_build_key(wand_xml)

        seen_builds[wand_build_key] = seen_builds[wand_build_key] or {}
        table.insert(seen_builds[wand_build_key], xml_file_name)
    end
end

print()
print("\n\n# Potential duplicates")
for key, names in pairs(seen_builds) do
    if #names > 1 then
        print("Wand build seen multiple times: " .. key)
        for _, name in ipairs(names) do
            print("- " .. name)
        end
    end
end

print("\n\n# Wand builds")
for key, names in pairs(seen_builds) do
    print("Name(s): " .. table.concat(names, ", "))
    print("Build: " .. key)
    print()
end
