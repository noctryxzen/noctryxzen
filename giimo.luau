--!strict

local FunctionButCloned: <T>(T) -> T = clonefunction or function<T>(f: T): T return f end

local GetService: (Instance, string) -> Instance = FunctionButCloned(game.GetService)
local Reference: (Instance) -> Instance = cloneref or function(X: Instance): Instance return X end
local SType: (any) -> string = FunctionButCloned(type)
local SPcall: ((...any) -> ...any, ...any) -> (boolean, ...any) = FunctionButCloned(pcall)
local SPairs: <K, V>({[K]: V}) -> ((any, any) -> (any, any), any, any) = FunctionButCloned(pairs)
local SWarn: (...any) -> () = FunctionButCloned(warn)
local SToString: (any) -> string = FunctionButCloned(tostring)
local SLower: (string) -> string = FunctionButCloned(string.lower)
local SFind: (string, string, number?, boolean?) -> (number?, number?) = FunctionButCloned(string.find)

local Services: {[string]: Instance} = setmetatable({}, {
	__index = function(S: any, N: string): Instance
		S[N] = Reference(GetService(game, N))
		return S[N]
	end
})

type HookOptions = {
	ScriptName: string?,
	FunctionName: string?,
	FunctionAddress: string?,
	FunctionHash: string?,
	ScriptHash: string?,
	Constants: {any}?,
	Upvalues: {string}?
}

type HookEntry = {
	Original: (...any) -> any,
	Active: boolean
}

local Bynew = {
	Hooks = {} :: {[(...any) -> any]: HookEntry}
}

local function GetExecutorName(): string
	local ok: boolean, Name: any = SPcall(identifyexecutor)
	return ok and Name or "idk this executor"
end

local function MatchesConstant(A: any, B: any): boolean
	if SType(A) == "string" and SType(B) == "string" then
		return SLower(A) == SLower(B)
	end
	return A == B
end

local function ShouldHook(Func: (...any) -> any, Options: HookOptions): boolean
	if not islclosure or not islclosure(Func) then return false end
	
	local ok: boolean, Info: any = SPcall(debug.getinfo, Func)
	if not ok or not Info then return false end
	
	if Options.ScriptName then
		if not Info.source then return false end
		local Source: string = SLower(SToString(Info.source))
		if not SFind(Source, SLower(Options.ScriptName), 1, true) then
			return false
		end
	end
	
	if Options.FunctionName then
		if not Info.name then return false end
		if SLower(Info.name) ~= SLower(Options.FunctionName) then
			return false
		end
	end
	
	if Options.FunctionAddress then
		local Addr: string = SToString(Func)
		local Start: number? = SFind(Addr, "0x", 1, true)
		local FuncAddr: string? = Start and Addr:sub(Start) or nil
		if not FuncAddr or SLower(FuncAddr) ~= SLower(Options.FunctionAddress) then
			return false
		end
	end
	
	if Options.FunctionHash then
		if not getfunctionhash then return false end
		local ok2: boolean, Hash: any = SPcall(getfunctionhash, Func)
		if not ok2 or Hash ~= Options.FunctionHash then
			return false
		end
	end
	
	if Options.ScriptHash then
		if not getscripthash or not getscripts then return false end
		
		local Source: string = Info.source
		if Source:sub(1, 1) == "@" then
			Source = Source:sub(2)
		end
		
		local AllScripts: {LuaSourceContainer} = getscripts()
		local FoundScript: LuaSourceContainer? = nil
		for i: number = 1, #AllScripts do
			local Scr: LuaSourceContainer = AllScripts[i]
			if Scr:GetFullName() == Source or Scr.Name == Source then
				FoundScript = Scr
				break
			end
		end
		
		if not FoundScript then return false end
		
		local ok2: boolean, Hash: any = SPcall(getscripthash, FoundScript)
		if not ok2 or Hash ~= Options.ScriptHash then
			return false
		end
	end
	
	if Options.Constants then
		if not debug.getconstants then return false end
		
		local ok2: boolean, Constants: any = SPcall(debug.getconstants, Func)
		if not ok2 or not Constants then return false end
		
		local Matches: number = 0
		for i: number = 1, #Constants do
			local Const: any = Constants[i]
			for j: number = 1, #Options.Constants do
				if MatchesConstant(Const, Options.Constants[j]) then
					Matches += 1
					break
				end
			end
		end
		
		if Matches ~= #Options.Constants then
			return false
		end
	end
	
	if Options.Upvalues then
		if not debug.getupvalues then return false end
		
		local ok2: boolean, Upvalues: any = SPcall(debug.getupvalues, Func)
		if not ok2 or not Upvalues then return false end
		
		local Matches: number = 0
		for Name: any, Value: any in SPairs(Upvalues) do
			if SType(Name) == "string" then
				local LowerName: string = SLower(Name)
				for i: number = 1, #Options.Upvalues do
					if LowerName == SLower(Options.Upvalues[i]) then
						Matches += 1
						break
					end
				end
			end
		end
		
		if Matches ~= #Options.Upvalues then
			return false
		end
	end
	
	return true
end

local function DisableFunction(Func: (...any) -> any): ()
	if debug.getconstants and debug.setconstant then
		local ok: boolean, Constants: any = SPcall(debug.getconstants, Func)
		if ok and Constants then
			for i: number = 1, #Constants do
				local Const: any = Constants[i]
				local ConstType: string = SType(Const)
				
				if ConstType == "string" then
					SPcall(debug.setconstant, Func, i, "")
				elseif ConstType == "number" then
					SPcall(debug.setconstant, Func, i, 0)
				elseif ConstType == "boolean" then
					SPcall(debug.setconstant, Func, i, false)
				end
			end
		end
	end
	
	if debug.getupvalues and debug.setupvalue then
		local ok: boolean, Upvalues: any = SPcall(debug.getupvalues, Func)
		if ok and Upvalues then
			for Name: any, Value: any in SPairs(Upvalues) do
				SPcall(debug.setupvalue, Func, Name, nil)
			end
		end
	end
	
	if debug.getprotos then
		local ok: boolean, Protos: any = SPcall(debug.getprotos, Func)
		if ok and Protos then
			for i: number = 1, #Protos do
				local Proto: any = Protos[i]
				if SType(Proto) == "function" then
					DisableFunction(Proto)
				end
			end
		end
	end
end

local function GetAllFunctions(): {any}
	local AllFuncs: {any} = {}
	local Processed: {[any]: boolean} = {}
	
	if filtergc then
		local ok: boolean, Result: any = SPcall(filtergc, "function")
		if ok and Result then
			local FuncList: {any} = SType(Result) == "table" and Result or {Result}
			for i: number = 1, #FuncList do
				if not Processed[FuncList[i]] then
					AllFuncs[#AllFuncs + 1] = FuncList[i]
					Processed[FuncList[i]] = true
				end
			end
		end
	end
	
	if getgc then
		local ok: boolean, GcFuncs: any = SPcall(getgc, false)
		if ok and GcFuncs then
			for i: number = 1, #GcFuncs do
				if SType(GcFuncs[i]) == "function" and not Processed[GcFuncs[i]] then
					AllFuncs[#AllFuncs + 1] = GcFuncs[i]
					Processed[GcFuncs[i]] = true
				end
			end
		end
	end
	
	local Reg: {any}? = nil
	if getreg then
		SPcall(function(): ()
			Reg = getreg()
		end)
	end
	
	if not Reg and getregistry then
		SPcall(function(): ()
			Reg = getregistry()
		end)
	end
	
	if Reg then
		for i: number = 1, #Reg do
			local Obj: any = Reg[i]
			if SType(Obj) == "function" and not Processed[Obj] then
				if isexecutorclosure and isexecutorclosure(Obj) then
					continue
				end
				
				if islclosure and not islclosure(Obj) then
					continue
				end
				
				AllFuncs[#AllFuncs + 1] = Obj
				Processed[Obj] = true
			end
		end
	end
	
	return AllFuncs
end

function Bynew.Find(PossibleAC: string?): {string}
	local Found: {string} = {}
	local FoundSet: {[string]: boolean} = {}
	
	if PossibleAC then
		if getgc then
			local ok: boolean, GcFuncs: any = SPcall(getgc, false)
			if ok and GcFuncs then
				for i: number = 1, #GcFuncs do
					if SType(GcFuncs[i]) == "function" then
						if isexecutorclosure and isexecutorclosure(GcFuncs[i]) then
							continue
						end
						
						if islclosure and not islclosure(GcFuncs[i]) then
							continue
						end
						
						local ok2: boolean, Info: any = SPcall(debug.getinfo, GcFuncs[i])
						if ok2 and Info and Info.source then
							local Source: string = SLower(SToString(Info.source))
							if SFind(Source, SLower(PossibleAC), 1, true) and not FoundSet[Info.source] then
								Found[#Found + 1] = Info.source
								FoundSet[Info.source] = true
							end
						end
					end
				end
			end
		end
		
		local Reg: {any}? = nil
		if getreg then
			SPcall(function(): ()
				Reg = getreg()
			end)
		end
		
		if not Reg and getregistry then
			SPcall(function(): ()
				Reg = getregistry()
			end)
		end
		
		if Reg then
			for i: number = 1, #Reg do
				local Obj: any = Reg[i]
				
				if SType(Obj) == "function" then
					if isexecutorclosure and isexecutorclosure(Obj) then
						continue
					end
					
					if islclosure and not islclosure(Obj) then
						continue
					end
					
					local ok: boolean, Info: any = SPcall(debug.getinfo, Obj)
					if ok and Info and Info.source then
						local Source: string = SLower(SToString(Info.source))
						if SFind(Source, SLower(PossibleAC), 1, true) and not FoundSet[Info.source] then
							Found[#Found + 1] = Info.source
							FoundSet[Info.source] = true
						end
					end
				end
			end
		end
		
		if #Found > 0 then
			for i: number = 1, #Found do
				SWarn(Found[i])
			end
		end
		
		if setclipboard then
			setclipboard(table.concat(Found, "\n"))
		elseif toclipboard then
			toclipboard(table.concat(Found, "\n"))
		end
		
		return Found
	end
	
	local FoundScripts: {[LuaSourceContainer]: string} = {}
	
	if getgc and getscripts then
		local ok: boolean, GcFuncs: any = SPcall(getgc, false)
		if ok and GcFuncs then
			for i: number = 1, #GcFuncs do
				if SType(GcFuncs[i]) == "function" then
					if isexecutorclosure and isexecutorclosure(GcFuncs[i]) then
						continue
					end
					
					if islclosure and not islclosure(GcFuncs[i]) then
						continue
					end
					
					local ok2: boolean, Info: any = SPcall(debug.getinfo, GcFuncs[i])
					if ok2 and Info and Info.source then
						local SrcName: string = Info.source
						if SrcName:sub(1, 1) == "@" then
							SrcName = SrcName:sub(2)
						end
						
						local AllScripts: {LuaSourceContainer} = getscripts()
						for j: number = 1, #AllScripts do
							local Scr: LuaSourceContainer = AllScripts[j]
							if (Scr:GetFullName() == SrcName or Scr.Name == SrcName) and (Scr:IsA("LocalScript") or Scr:IsA("ModuleScript") or Scr:IsA("Script")) then
								if not FoundScripts[Scr] then
									FoundScripts[Scr] = "GC"
								end
							end
						end
					end
				end
			end
		end
	end
	
	local Reg: {any}? = nil
	if getreg then
		SPcall(function(): ()
			Reg = getreg()
		end)
	end
	
	if not Reg and getregistry then
		SPcall(function(): ()
			Reg = getregistry()
		end)
	end
	
	if Reg and getscripts then
		for i: number = 1, #Reg do
			local Obj: any = Reg[i]
			
			if SType(Obj) == "function" then
				if isexecutorclosure and isexecutorclosure(Obj) then
					continue
				end
				
				if islclosure and not islclosure(Obj) then
					continue
				end
				
				local ok: boolean, Info: any = SPcall(debug.getinfo, Obj)
				if ok and Info and Info.source and Info.source:sub(1, 1) == "@" then
					local SrcName: string = Info.source:sub(2)
					
					local AllScripts: {LuaSourceContainer} = getscripts()
					for j: number = 1, #AllScripts do
						local Scr: LuaSourceContainer = AllScripts[j]
						if (Scr:GetFullName() == SrcName or Scr.Name == SrcName) and (Scr:IsA("LocalScript") or Scr:IsA("ModuleScript") or Scr:IsA("Script")) then
							if not FoundScripts[Scr] then
								FoundScripts[Scr] = "Reg"
							end
						end
					end
				end
			end
		end
	end
	
	local ok: boolean, RepFirst: any = SPcall(function(): Instance
		return Services.ReplicatedFirst
	end)
	
	if ok and RepFirst then
		for idx: number, Child: Instance in RepFirst:GetDescendants() do
			if Child:IsA("LocalScript") or Child:IsA("ModuleScript") or Child:IsA("Script") then
				FoundScripts[Child] = "ReplicatedFirst"
			end
		end
	end
	
	if getnilinstances then
		local ok2: boolean, NilInsts: any = SPcall(getnilinstances)
		if ok2 and NilInsts then
			for idx: number, Inst: any in NilInsts do
				if SType(Inst) == "userdata" and typeof(Inst) == "Instance" then
					if Inst:IsA("LocalScript") or Inst:IsA("ModuleScript") or Inst:IsA("Script") then
						FoundScripts[Inst] = "Nil"
					end
				end
			end
		end
	end
	
	if getactors then
		local ok2: boolean, Actors: any = SPcall(getactors)
		if ok2 and Actors then
			for idx: number = 1, #Actors do
				SPcall(function(): ()
					local Act: Actor = Actors[idx]
					for DescIdx: number, Desc: Instance in Act:GetDescendants() do
						if Desc:IsA("LocalScript") or Desc:IsA("ModuleScript") or Desc:IsA("Script") then
							FoundScripts[Desc] = "Actor"
						end
					end
				end)
			end
		end
	end
	
	for Scr: LuaSourceContainer, Category: string in FoundScripts do
		local Name: string = ""
		if Category == "Nil" then
			Name = `Nil.{Scr.Name}`
		elseif Category == "Actor" then
			Name = `Actor.{Scr:GetFullName()}`
		elseif Category == "ReplicatedFirst" then
			Name = Scr:GetFullName()
		end
		
		if #Name > 0 and not FoundSet[Name] then
			Found[#Found + 1] = Name
			FoundSet[Name] = true
		end
	end
	
	if #Found > 0 then
		for i: number = 1, #Found do
			SWarn(Found[i])
		end
	end
	
	if setclipboard then
		setclipboard(table.concat(Found, "\n"))
	elseif toclipboard then
		toclipboard(table.concat(Found, "\n"))
	end
	
	return Found
end

function Bynew.Hook(Options: string | HookOptions, Callback: ((fn: (...any) -> any) -> ())?): number
	if not (getgc or filtergc or getreg or getregistry) then
		SWarn(`[{GetExecutorName()}] doesn't support: getgc, filtergc, getreg or getregistry`)
		return 0
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Functions: {any} = GetAllFunctions()
	local Hooked: number = 0
	
	for i: number = 1, #Functions do
		local Func: any = Functions[i]
		
		if SType(Func) == "function" and ShouldHook(Func, HookOpts) then
			if not Bynew.Hooks[Func] or not Bynew.Hooks[Func].Active then
				local Original: (...any) -> any = FunctionButCloned(Func)
				
				if Callback then
					Callback(Func)
				else
					DisableFunction(Func)
				end
				
				Bynew.Hooks[Func] = {
					Original = Original,
					Active = true
				}
				
				Hooked += 1
			end
		end
	end
	
	return Hooked
end

function Bynew.Replace(Options: string | HookOptions, Replacement: (...any) -> any): number
	if not hookfunction then
		SWarn(`[{GetExecutorName()}] doesn't support: hookfunction`)
		return 0
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Functions: {any} = GetAllFunctions()
	local Replaced: number = 0
	
	for i: number = 1, #Functions do
		local Func: any = Functions[i]
		
		if SType(Func) == "function" and ShouldHook(Func, HookOpts) then
			if not Bynew.Hooks[Func] or not Bynew.Hooks[Func].Active then
				local Original: (...any) -> any = hookfunction(Func, Replacement)
				
				Bynew.Hooks[Func] = {
					Original = Original,
					Active = true
				}
				
				Replaced += 1
			end
		end
	end
	
	return Replaced
end

function Bynew.Restore(Options: string | HookOptions?): number
	if not restorefunction then
		SWarn(`[{GetExecutorName()}] doesn't support: restorefunction`)
		return 0
	end
	
	if not Options then
		local Restored: number = 0
		for Func: any, Entry: any in SPairs(Bynew.Hooks) do
			if Entry.Active then
				SPcall(restorefunction, Func)
				Entry.Active = false
				Restored += 1
			end
		end
		return Restored
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Restored: number = 0
	
	for Func: any, Entry: any in SPairs(Bynew.Hooks) do
		if Entry.Active and ShouldHook(Func, HookOpts) then
			SPcall(restorefunction, Func)
			Entry.Active = false
			Restored += 1
		end
	end
	
	return Restored
end

return Bynew
