#define SCRIPT_IS_ROOT
#define USE_EVENTS
#define ALLOW_USER_DEBUG 1
#include "got/_core.lsl"

integer slave;
list PLAYERS = [];
list PLAYERS_COMPLETED;
integer START_PARAM;

integer DEATHS;
integer MONSTERS_KILLED;

integer BFL;
#define BFL_MONSTERS_LOADED 0x1
#define BFL_ASSETS_LOADED 0x2
#define BFL_LOADING 0x4
#define BFL_SCRIPTS_LOADED 0x8
#define BFL_INI 0x10
#define BFL_LOAD_REQ (BFL_MONSTERS_LOADED|BFL_ASSETS_LOADED|BFL_SCRIPTS_LOADED)
#define BFL_COMPLETED 0x20
// Prevents auto load from running multiple times when the level is rezzed live
#define BFL_AUTOLOADED 0x40


list LOADQUEUE = REQUIRE;			// Required scripts to be remoteloaded
list LOAD_ADDITIONAL = [];			// Scripts from description we need to wait for

onEvt(string script, integer evt, list data){
	if(evt == evt$SCRIPT_INIT && ~BFL&BFL_INI){
		integer pos = llListFindList(LOADQUEUE, [script]);
		if(~pos){
			LOADQUEUE = llDeleteSubList(LOADQUEUE, pos, pos);
			
			if(LOADQUEUE == []){
				
				// Loadqueue raises script init with the pin that other scripts can use once the official scripts have been downloaded
				db3$set([LevelShared$isSharp], (string)START_PARAM);
				raiseEvent(evt$SCRIPT_INIT, (str)pin);				
				
			} 
		}
		
		pos = llListFindList(LOAD_ADDITIONAL, [script]);
		if(~pos){
			LOAD_ADDITIONAL = llDeleteSubList(LOAD_ADDITIONAL, pos, pos);
		}
		
		// Load finished
		if(LOADQUEUE+LOAD_ADDITIONAL == [] && ~BFL&BFL_INI){
			Alert$freetext(llGetOwner(), "Loading from HUD", FALSE, FALSE);
			Root$setLevel();
			BFL = BFL|BFL_INI;
		}
		
	}
	
	if(script == "got LevelLoader" && evt == LevelLoaderEvt$defaultStatus){
		
		integer assets = l2i(data, 0);
		integer spawns = l2i(data, 1);
		
		if(!assets){
			Level$loaded(LINK_THIS, 0);
		}
		if(!spawns){
			Level$loaded(LINK_THIS, 1);
		}
		
		if(!assets || !spawns){
			multiTimer(["LOAD_FINISH", "", 60, FALSE]);
		}
	}
	
	
}

timerEvent(string id, string data){
	
	if(id == "INI"){
		if(~BFL&BFL_INI){
			llOwnerSay("got Level @ timer(): Level script could not update. If you are developing this level, wear the HUD and then reset the level script.");
		}
		Root$setLevel();
	}
	
	else if(id == "LOAD_FINISH"){
		Level$loadFinished();
		Root$setLevel();
	}

}

integer pin;
default
{
    on_rez(integer mew){
        llSetText((string)mew, ZERO_VECTOR, 0);
		pin = floor(llFrand(0xFFFFFFF));
		llSetRemoteScriptAccessPin(pin);
        Remoteloader$load(cls$name, pin, 2);
		llResetScript();
    }
    
    state_entry()
    {
		resetAllOthers();
		initiateListen();
		PLAYERS = [(string)llGetOwner()];
		
		// Rez param
		START_PARAM = llList2Integer(llGetLinkPrimitiveParams(LINK_THIS, [PRIM_TEXT]), 0);
		
		// On remoteload
		if(llGetStartParameter() == 2){
			
			list tables = [
				LevelStorage$main,
				LevelStorage$points,
				LevelStorage$custom,
				LevelStorage$points+"_1",
				LevelStorage$custom+"_1",
				LevelStorage$points+"_2",
				LevelStorage$custom+"_2"
			];
			db3$addTables(tables);
			
			vector p = llGetPos();
			vector pos = p-vecFloor(p)+int2vec(START_PARAM);
			
			if(START_PARAM == 1)pos = ZERO_VECTOR;

			if(START_PARAM&(BIT_DEBUG-1))llSetRegionPos(pos);
			
			list refresh = ["Trigger", "TriggerSensor"];
			while(llGetListLength(refresh)){
				string val = llList2String(refresh,0); 
				refresh = llDeleteSubList(refresh,0,0);  
				if(llGetInventoryType(val) != INVENTORY_NONE){ 
					llRemoveInventory(val); 
					llSleep(.1); 
					Spawner$getAsset(val);
				} 
			}
			
			
			
			
			pin = floor(llFrand(0xFFFFFFF));
			llSetRemoteScriptAccessPin(pin);
			
			Remoteloader$load(mkarr(LOADQUEUE), pin, 2);
			
			// Add custom scripts that need to init
			if(llJsonValueType(llGetObjectDesc(), []) == JSON_ARRAY){
				list d = llJson2List(llGetObjectDesc());
				list_shift_each(d, val,
					list v = llJson2List(val);
					integer type = l2i(v, 0);
					v = llDeleteSubList(v, 0,0);
					
					// Custom scripts
					if(type == LevelDesc$additionalScripts){
						list_shift_each(v, script,
							if(llListFindList(LOAD_ADDITIONAL, [script]) == -1){
								LOAD_ADDITIONAL += script;
							}
						)
					}
					
				)
			}
			
			
			return;
        }
		multiTimer(["INI", "", 5, FALSE]);
		
    }
    
    timer(){
		multiTimer([]);
    }

    #define LISTEN_LIMIT_FREETEXT if(llListFindList(PLAYERS, [(string)llGetOwnerKey(id)]) == -1){return;}
    #include "xobj_core/_LISTEN.lsl"
    
    #include "xobj_core/_LM.lsl"
    /*
        Included in all these calls:
        METHOD - (int)method
        PARAMS - (var)parameters
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task
    */
// Spawn the level, this goes first as it's fucking memory intensive
    if(METHOD == LevelMethod$load && method$byOwner){
		integer debug = (integer)method_arg(0);
		string group = method_arg(1);
		
        raiseEvent(LevelEvt$load, mkarr(([debug, group])));

		// Things to run on level start
		if(group == ""){
			BFL = BFL&~BFL_COMPLETED;
			BFL = BFL&~BFL_MONSTERS_LOADED;
			BFL = BFL&~BFL_ASSETS_LOADED;
			BFL = BFL|BFL_LOADING;
			
			multiTimer(["LOAD_FINISH", "", 10, FALSE]);
			
			Bridge$getCellData();
			
			vector p1 = (vector)db3$get(cls$name, [LevelShared$P1_start]);
			vector p2 = (vector)db3$get(cls$name, [LevelShared$P2_start]); 
			if(debug){
				if(p1)
					Devtool$spawnAt("_STARTPOINT_P1", p1+llGetPos(), ZERO_ROTATION);
				if(p2)
					Devtool$spawnAt("_STARTPOINT_P2", p2+llGetPos(), ZERO_ROTATION);
			}else{
				// Send player to start
				Alert$freetext(llGetOwner(), "Loading Cell.. Please wait.", FALSE, FALSE);
				
				
				vector p1 = (vector)db3$get(cls$name, [LevelShared$P1_start]);
				vector p2 = (vector)db3$get(cls$name, [LevelShared$P2_start]); 
				
				// Adds a 6 sec delay for physics shapes to load
				list tp = [
					SupportcubeBuildTask(Supportcube$tSetPos, [prPos(l2s(PLAYERS, 0))]), 
					SupportcubeBuildTask(Supportcube$tDelay, [.1]), 
					SupportcubeBuildTask(Supportcube$tForceSit, ([FALSE, TRUE])), 
					SupportcubeBuildTask(Supportcube$tSetPos, [p1+llGetPos()]), 
					SupportcubeBuildTask(Supportcube$tDelay, [6]), 
					SupportcubeBuildTask(Supportcube$tForceUnsit, [])
				];
				RLV$cubeTaskOn(llList2String(PLAYERS, 0), tp);
				
				// Send anyways to preserve memory
				vector two = p2;
				if(two == ZERO_VECTOR)two = p1;
				
				tp = [
					SupportcubeBuildTask(Supportcube$tSetPos, [prPos(l2s(PLAYERS, 0))]), 
					SupportcubeBuildTask(Supportcube$tDelay, [.1]), 
					SupportcubeBuildTask(Supportcube$tForceSit, ([FALSE, TRUE])), 
					SupportcubeBuildTask(Supportcube$tSetPos, [two+llGetPos()]), 
					SupportcubeBuildTask(Supportcube$tDelay, [6]), 
					SupportcubeBuildTask(Supportcube$tForceUnsit, [])
				];
				RLV$cubeTaskOn(llList2String(PLAYERS, 1), tp);

			}
			
			runOnPlayers(pk, 
				Root$setLevelOn(pk);
				if(!debug)Status$loading(pk, TRUE);
				GUI$toggleSpinner(pk, TRUE, "");
			)
        }
		
		// These will be run even when loading a custom group
		
		LevelLoader$load(debug, group);
        return;
    }
	
	
	
    if(method$isCallback){
		// Players grabbed
        if(CB == "LV" && SENDER_SCRIPT == "#ROOT" && llGetOwnerKey(id) == llGetOwner() && llGetStartParameter() == 2 && method$byOwner){
            PLAYERS = PARAMS;
			if(llList2Key(PLAYERS, 0)){
				// prevents recursion
				if(BFL&BFL_AUTOLOADED)
					return;
					
				BFL = BFL|BFL_AUTOLOADED;
				
				list pnames = [];
				raiseEvent(LevelEvt$players, mkarr(PARAMS));
				
				
				runOnPlayers(targ,
					pnames += llGetDisplayName(targ);
					GUI$toggleBoss(targ, "", FALSE);
					Rape$setTemplates(targ, []);
					Root$setLevelOn(targ);
				)
				
				multiTimer(["INI"]);
				Alert$freetext(llGetOwner(), "Players: "+implode(", ", pnames), FALSE, FALSE);
				if(START_PARAM){
					runMethod((string)LINK_THIS, cls$name, LevelMethod$load, [FALSE], TNN);
				}
			}
        }
        return;
    }
	
	

	
	
    
// PUBLIC HERE
    if(METHOD == LevelMethod$interact){
        return raiseEvent(LevelEvt$interact, mkarr(([llGetOwnerKey(id), method_arg(0), method_arg(1)]))); 
    }
    if(METHOD == LevelMethod$trigger){
        return raiseEvent(LevelEvt$trigger, mkarr(([method_arg(0), id, method_arg(1)])));   
    }
    if(METHOD == LevelMethod$idEvent){
        list out = [id, method_arg(1), method_arg(2), method_arg(3)];
        integer evt = (integer)method_arg(0);
		if(evt == LevelEvt$idDied){
			MONSTERS_KILLED++;
		}
        return raiseEvent(evt, mkarr(out));
    }
	if(METHOD == LevelMethod$died){
		DEATHS++;
		return;
	}
	if(METHOD == LevelMethod$getObjectives){
		return raiseEvent(LevelEvt$fetchObjectives, mkarr([llGetOwnerKey(id)]));
	}
	if(METHOD == LevelMethod$bindToLevel){
		return Root$setLevelOn(id);
	}
	
	if(METHOD == LevelMethod$spawn){
        runMethod((str)LINK_THIS, "got LevelAux", LevelAuxMethod$spawn, PARAMS, TNN);
        return;
    }
    
// OWNER ONLY
	if(METHOD == LevelMethod$setFinished && method$byOwner){
		integer added;
		if((integer)method_arg(0) == -1){
			PLAYERS_COMPLETED = PLAYERS;
		}
        else if(llListFindList(PLAYERS_COMPLETED, [method_arg(0)]) == -1 && method_arg(0) != ""){		
			PLAYERS_COMPLETED += [method_arg(0)];
			added = TRUE;
		}
		
		// Done
        if(PLAYERS_COMPLETED == PLAYERS && ~BFL&BFL_COMPLETED){
			runOnPlayers(targ,
				GUI$toggleObjectives(targ, FALSE); // Clear objectives
			)
			
			// Tell the _main that the level is finished
			if((integer)method_arg(1)){
				raiseEvent(LevelEvt$levelCompleted, "");
				return;
			}
            
			// Actually send the completecell command, but only once
			if((integer)START_PARAM){
				BFL = BFL|BFL_COMPLETED;
                runOnPlayers(pk, 
					integer continue = (pk == llGetOwner());
					Bridge$completeCell(pk, DEATHS, MONSTERS_KILLED, continue);
					Portal$killAll();
				)
				qd("Loading next stage.");
				return;
            }
            llOwnerSay("Cell test completed!");
			return;
        }
		else if(added){
			// Not done
			integer i;
			for(i=0; i<llGetListLength(PLAYERS); i++){
				string msg = "Someone has reached the level exit.";
				if(llListFindList(PLAYERS_COMPLETED, [llList2String(PLAYERS, i)]) == -1){
					msg += " Waiting for you to do the same.";
				}else{
					msg += " Waiting for coop player.";
				}
				Alert$freetext(llList2Key(PLAYERS, i), msg, TRUE, TRUE);
			}
		}
		return;
    }
	
	if(METHOD == LevelMethod$getPlayers)
		raiseEvent(LevelEvt$players, mkarr(PLAYERS));
   
    
    if(METHOD == LevelMethod$loaded && BFL&BFL_LOADING && method$byOwner){
        integer isHUD = (integer)method_arg(0);
        if(isHUD == 2)BFL = BFL|BFL_SCRIPTS_LOADED;
        else if(isHUD)BFL = BFL|BFL_MONSTERS_LOADED;
        else BFL = BFL|BFL_ASSETS_LOADED;
				
        if((BFL&BFL_LOAD_REQ) == BFL_LOAD_REQ){
            Level$loadFinished();
        }
    }
	
	if(METHOD == LevelMethod$potionUsed){
		raiseEvent(LevelEvt$potion, mkarr(([llGetOwnerKey(id), method_arg(0)])));
	}
	
	if(METHOD == LevelMethod$cellData && method$byOwner){
		string dta = method_arg(0);
		db3$set([LevelShared$questData], dta);
		raiseEvent(LevelEvt$questData, dta);
	}
	if(METHOD == LevelMethod$cellDesc && method$byOwner){
		string txt = method_arg(0);
		if(~BFL&BFL_LOAD_REQ && isset(txt)){	// One of the items required for load is not set
			runOnPlayers(pk,
				GUI$toggleSpinner(pk, TRUE, txt);
			)
		}
	}
    if(METHOD == LevelMethod$loadFinished && BFL&BFL_LOADING && method$byOwner){
		
		qd("Level has finished loading");
		
		multiTimer(["LOAD_FINISH"]);
        BFL = BFL&~BFL_LOADING;
        raiseEvent(LevelEvt$loaded, "");
		
		runOnPlayers(pk, 
			Status$loading(pk, FALSE);
            GUI$toggleSpinner(pk, FALSE, "");
		)

    }

    if(METHOD == LevelMethod$despawn && method$byOwner){
        llDie();
    }
	if(METHOD == LevelMethod$update && method$byOwner){
		// Grab script update
		pin = floor(llFrand(0xFFFFFFF));
		llSetRemoteScriptAccessPin(pin);
        Remoteloader$load(cls$name, pin, 2);
		qd("Updating level code...");
	}
    
    
    
    
    

    if(METHOD == LevelMethod$getScripts && method$byOwner){
        integer pin = l2i(PARAMS, 0);
        list scripts = llJson2List(method_arg(1));
        list_shift_each(scripts, v, 
            if(llGetInventoryType(v) == INVENTORY_SCRIPT){
                slave++;
                if(slave>9)slave=1;
                // Remote load
                llMessageLinked(LINK_THIS, slave, llList2Json(JSON_ARRAY, [id, v, pin, 2]), "rm_slave");
            }
            else if(llGetInventoryType(v) != INVENTORY_NONE) llGiveInventory(id, v);
        )
    }
    
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl" 
    
    
}

