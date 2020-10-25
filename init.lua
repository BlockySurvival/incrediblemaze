
--config:

--materials: only change the node IDs "<here>".
--material used to fill free space (default: "air")
local c_air=minetest.get_content_id("air")
--material used to make walls inside the maze (default: "default:cobble")
local c_wall=minetest.get_content_id("default:cobble")
--material used to construct the pillar grid (default: "default:desert_cobble")
local c_pillar=minetest.get_content_id("default:desert_cobble")
--material used to surround the whole maze with (default: "default:desert_cobble")
local c_outerwall=minetest.get_content_id("default:desert_cobble")

--divider value in space calculation. default: 6
--rough determination where to set the passage into a line if setting it is not enforced by a crossed wall
--leaving this at the default is probably the best
local m_space_divider=6
--- end of config ---

local dirmap={
	{z=1, x=0},
	{x=1, z=0},
	{z=-1, x=0},
	{x=-1, z=0},
}

--all variables are in file scope, for functions to access them
local bmin, bmax, emin, emax, data, area, at_node, pr_node, m_size_x, m_size_z, m_spaceprob

local rint=function(m,n) return math.floor(math.random(m,n)+0.5) end

local function is_invalid_node(pos)
	return pos.x<0 or pos.z<0 or pos.x>m_size_x or pos.z>m_size_z
end
local function proceed(at, pr)
	local dx, dz = (at.x-pr.x), (at.z-pr.z)
	return {x=at.x+dx, z=at.z+dz}
end
local function get_edge(p1, p2)
	if is_invalid_node(p1) or is_invalid_node(p2) then return true end
	local mtn1, mtn2={x=2*p1.x, z=2*p1.z}, {x=2*p2.x, z=2*p2.z}
	local x,z = (mtn1.x+mtn2.x)/2, (mtn1.z+mtn2.z)/2
	local i=area:indexp({x=bmin.x+x, y=bmin.y, z=bmin.z+z})
	return data[i]~=c_air
end
local function set_edge(p1, p2, wall)
	local mtn1, mtn2={x=2*p1.x, z=2*p1.z}, {x=2*p2.x, z=2*p2.z}
	local x,z = (mtn1.x+mtn2.x)/2, (mtn1.z+mtn2.z)/2
	for y=bmin.y, bmax.y do
		local i=area:indexp({x=bmin.x+x, y=y, z=bmin.z+z})
		data[i]= wall and c_wall or c_air
	end
end

local function v_add(p1, p2)
	return {x=p1.x+p2.x, z=p1.z+p2.z}
end


local function run_cmd(name,param)
	local t1=os.clock()
	
	if tonumber(param) then
		math.randomseed(param)
	end
	
	local wep1, wep2=worldedit.pos1[name], worldedit.pos2[name]
	if not wep1 or not wep2 then
		return false,"Please set both WE positions"
	end
	wep1, wep2=vector.sort(wep1, wep2)
	if wep2.y-wep1.y<1 then
		return false,"Height difference has to be at least 1, but 2 is most useful."
	end
	m_size_x=math.floor((wep2.x-wep1.x)/2)
	m_size_z=math.floor((wep2.z-wep1.z)/2)
	
	m_spaceprob = (m_size_x+m_size_z)/m_space_divider
	
	local vmanip = minetest.get_voxel_manip()
	bmin, bmax = wep1, {x=wep1.x+2*m_size_x, y=wep2.y, z=wep1.z+2*m_size_z}
	
	minetest.chat_send_player(name, "Preparing generation of maze of size "..m_size_x.."x"..m_size_z.." between "..minetest.pos_to_string(bmin).." and "..minetest.pos_to_string(bmin))
	
	emin, emax = vmanip:read_from_map(bmin, bmax)
	-- 1. create grid
	data = vmanip:get_data()
	
	area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local modx, modz = bmin.x%2, bmin.z%2
	for y=bmin.y,bmax.y do
		for x=bmin.x,bmax.x do
			for z=bmin.z,bmax.z do
				local i=area:indexp({x=x, y=y, z=z})
				if x%2==modx and z%2==modz then
					data[i]=c_pillar
				elseif x==bmin.x or z==bmin.z or x==bmax.x or z==bmax.z then
					data[i]=c_outerwall
				else
					data[i]=c_air
				end
			end
		end
	end

	local s_pos_list={}
	for z=1,m_size_z-1 do
		if rint(0,1)==0 then
			s_pos_list[#s_pos_list+1]={
				at_node={x=0, z=z},
				pr_node={x=-1, z=z},
			}
		else
			s_pos_list[#s_pos_list+1]={
				at_node={x=m_size_x, z=z},
				pr_node={x=m_size_x+1, z=z},
			}
		end
	end
	for x=1,m_size_x-1 do
		if rint(0,1)==0 then
			s_pos_list[#s_pos_list+1]={
				at_node={x=x, z=0},
				pr_node={x=x, z=-1},
			}
		else
			s_pos_list[#s_pos_list+1]={
				at_node={x=x, z=m_size_z},
				pr_node={x=x, z=m_size_z+1},
			}
		end
	end

	minetest.chat_send_player(name, "Starting to generate, "..#s_pos_list.." lines to fill.")

	while #s_pos_list>0 do
		local entrynum=rint(1,#s_pos_list)
		local entry=s_pos_list[entrynum]
		table.remove(s_pos_list, entrynum)
		local at_node, pr_node=entry.at_node, entry.pr_node
		local space_added=nil
		-- B proceed nodes until edge
		while true do
			local ne_node
			local crossing_wall, add_space=false, (not space_added and rint(0,m_spaceprob)==0)
			
			ne_node = proceed(at_node, pr_node)
			if get_edge(at_node, ne_node) then
				break
			end
			-- check if any neighboring edge of ne_node is a wall
			for eside=1,4 do
				if get_edge(ne_node, v_add(ne_node, dirmap[eside])) then
					crossing_wall=true
				end
			end
			if crossing_wall then
				if not space_added then
					add_space=true
				end
			end
			if add_space then
				space_added=true
			else
				set_edge(at_node, ne_node, true, line)
			end
			pr_node=at_node
			at_node=ne_node
			if crossing_wall then
				space_added=false
			end
		end
	end
	
	minetest.chat_send_player(name, "Generation completed, writing to map...")

	vmanip:set_data(data)
	vmanip:write_to_map()
	vmanip:update_map()
	
	local t2=os.clock()
	return true, "Generating maze completed in "..((t2-t1)*1000).."ms"
end

minetest.register_chatcommand("maze", {
	params = "<seed>",
	description = "Generate an Incredible Maze inside the WorldEdit area",
	privs = {worldedit=true},
	func=run_cmd,
})
