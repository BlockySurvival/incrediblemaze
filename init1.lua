local m_size_x=20
local m_size_z=20
local m_numlines=20
local m_spaceprob=4

local function print_concat_table(a)
	local str=""
	local stra=""
	for i=1,50 do
		t=a[i]
		if t==nil then
			stra=stra.."nil "
		else
			str=str..stra
			stra=""
			if type(t)=="table" then
				if t.x and t.y and t.z then
					str=str..minetest.pos_to_string(t)
				elseif t.x and t.z then
					str=str.."("..t.x.."|"..t.z..")"
				else
					str=str..dump(t)
				end
			elseif type(t)=="boolean" then
				if t then
					str=str.."true"
				else
					str=str.."false"
				end
			else
				str=str..t
			end
			str=str.." "
		end
	end
	return str
end
dprint=function(t, ...)
	local text=print_concat_table({t, ...})
	minetest.log("action", "[maze]"..text)
	minetest.chat_send_all("[maze]"..text)
end

local c_air=minetest.get_content_id("air")
local c_cobble=minetest.get_content_id("default:cobble")
local c_dcobble=minetest.get_content_id("default:desert_cobble")
local c_sand=minetest.get_content_id("default:sand")

local c_wools={
	minetest.get_content_id("wool:white"),
	minetest.get_content_id("wool:red"),
	minetest.get_content_id("wool:green"),
	minetest.get_content_id("wool:blue"),
	minetest.get_content_id("wool:yellow"),
	minetest.get_content_id("wool:orange"),
}

local dirmap={
	{z=1, x=0},
	{x=1, z=0},
	{z=-1, x=0},
	{x=-1, z=0},
}

--all variables are in file scope, for functions to access them
local bmin, bmax, emin, emax, data, area, at_node, pr_node

local rint=function(m,n) return math.floor(math.random(m,n)+0.5) end

local function is_invalid_node(pos)
	return pos.x<0 or pos.z<0 or pos.x>m_size_x or pos.z>m_size_z
end
local function proceed(at, pr, dir)
	local dx, dz = (at.x-pr.x), (at.z-pr.z)
	if dir==-1 then
		dx, dz = -dz, dx
	elseif dir==1 then
		dx, dz = dz, -dx
	end
	return {x=at.x+dx, z=at.z+dz}
end
local function get_edge(p1, p2)
	if is_invalid_node(p1) or is_invalid_node(p2) then return true end
	local mtn1, mtn2={x=2*p1.x, z=2*p1.z}, {x=2*p2.x, z=2*p2.z}
	local mtmed={x=(mtn1.x+mtn2.x)/2, y=0, z=(mtn1.z+mtn2.z)/2}
	local i=area:indexp(mtmed)
	return data[i]~=c_air
end
local function set_edge(p1, p2, wall, woolc)
	local mtn1, mtn2={x=2*p1.x, z=2*p1.z}, {x=2*p2.x, z=2*p2.z}
	local mtmed={x=(mtn1.x+mtn2.x)/2, y=0, z=(mtn1.z+mtn2.z)/2}
	local i=area:indexp(mtmed)
	data[i]= wall and c_cobble or c_air
end
local function set_sand(p1, p2)
	local mtn1, mtn2={x=2*p1.x, z=2*p1.z}, {x=2*p2.x, z=2*p2.z}
	local mtmed={x=(mtn1.x+mtn2.x)/2, y=0, z=(mtn1.z+mtn2.z)/2}
	local i=area:indexp(mtmed)
	data[i]= c_sand
end
local function v_add(p1, p2)
	return {x=p1.x+p2.x, z=p1.z+p2.z}
end


local function generate(name,param)
	math.randomseed(param)
	
	local vmanip = minetest.get_voxel_manip()
	bmin, bmax = {x=0, y=0, z=0}, {x=2*m_size_x, y=0, z=2*m_size_z}
	emin, emax = vmanip:read_from_map(bmin, bmax)
	dprint("Requested",bmin, bmax, " emerged",emin,emax)
	-- 1. create grid
	data = vmanip:get_data()
	
	area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	for x=bmin.x,bmax.x do
		for z=bmin.z,bmax.z do
			local i=area:indexp({x=x, y=0, z=z})
			if x%2==0 and z%2==0 then
				data[i]=c_dcobble
			elseif x==bmin.x or z==bmin.z or x==bmax.x or z==bmax.z then
				data[i]=c_dcobble
			else
				data[i]=c_air
			end
		end
	end
	
	for line=1,m_numlines do
		--draw lines from one border to another
		-- A select starting point
		-- 1:x=0 2:z=0, 3:x=max, 4:z=max
		local spointside=rint(1,4)
		if spointside==1 then
			at_node={x=0, z=rint(1, m_size_z-1)}
			pr_node={x=-1, z=at_node.z}
		elseif spointside==2 then
			at_node={x=rint(1, m_size_x-1), z=0}
			pr_node={x=at_node.x, z=-1}
		elseif spointside==3 then
			at_node={x=m_size_x, z=rint(1, m_size_z-1)}
			pr_node={x=m_size_x+1, z=at_node.z}
		elseif spointside==4 then
			at_node={x=rint(1, m_size_x-1), z=m_size_z}
			pr_node={x=at_node.x, z=m_size_z+1}
		end
		dprint("starting line at", at_node, pr_node)
		local isstart, space_added=true, nil
		local ownrte={}
		-- B proceed nodes until edge
		while true do
			local ne_node
			local crossing_wall, add_space=false, (not space_added and rint(0,m_spaceprob)==0)
			local prob={}
			for prodir=0,0 do
				local test_ne
				test_ne = proceed(at_node, pr_node, prodir)
				if not get_edge(at_node, test_ne) then
					prob[#prob+1]=test_ne
					if prodir==0 then --add straight triple, for higher probability
						prob[#prob+1]=test_ne
						prob[#prob+1]=test_ne
					end
				end
			end
			if #prob==0 then
				dprint("can't continue from",at_node,", break")
				break
			else
				ne_node=prob[rint(1,#prob)]
			end
			dprint("proceeding to", ne_node, "from", at_node)
			isstart=false
			-- I check if any neighboring edge of ne_node is a wall
			for eside=1,4 do
				if get_edge(ne_node, v_add(ne_node, dirmap[eside])) then
					crossing_wall=true
					dprint("crossing wall (side",eside,") setspace",space_added)
				end
			end
			if crossing_wall then
				if not space_added then
					dprint("crossing wall: needs to add space here")
					add_space=true
				end
				for _,ps in ipairs(ownrte) do
					if ps.x==ne_node.x and ps.z==ne_node.z then
						dprint("crossing own route: needs to add space here")
						add_space=true
					end
				end
			end
			if add_space then
				space_added=true
				--set_sand(at_node, ne_node)
				dprint("added space")
			else
				set_edge(at_node, ne_node, true, line)
				dprint("painting wall")
			end
			pr_node=at_node
			at_node=ne_node
			ownrte[#ownrte+1]=pr_node
			if crossing_wall then
				space_added=false
			end
		end
	end
	
	vmanip:set_data(data)
	vmanip:write_to_map()
	vmanip:update_map()
end

minetest.register_chatcommand("maze", {
	func=generate,
})
