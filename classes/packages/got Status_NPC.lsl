#define USE_EVENTS
//#define DEBUG DEBUG_UNCOMMON
#include "got/_core.lsl"

list PLAYERS;

float maxHP = 100;

// Conf stuff
float dmg = 10;         // Damage of melee attacks
float HP = 100;
float aggro_range;
key aggrosound;         //
key dropaggrosound;     //
key takehitsound;       //
key attacksound;        //
key deathsound;         // 
key icon;
string rapeName;        // Usually prim name

// (float)aggro, (key)id, (int)flags
#define AGGRO_STRIDE 3
list AGGRO;
#define AGFLAG_NOT_AGGROD 1

key aggroTarg;

integer BFL = 0; 
#define BFL_DEAD 0x1
#define BFL_FRIENDLY 0x2
#define BFL_STATUS_TIMER 0x4 

#define BFL_NOAGGRO (BFL_FRIENDLY|BFL_DEAD)

// Effects
integer STATUS_FLAGS = 0; 
// See ots Monster
integer RUNTIME_FLAGS;

// FX
integer FXFLAGS = 0;
float fxModDmgTaken = 1;
float fxModDmgDone = 1;

list SPELL_DMG_TAKEN_MOD;

#define SPSTRIDE 2
list SPELL_ICONS;   // [(key)texture, (int)desc]

list OUTPUT_STATUS_TO; 

dropAggro(key player, integer complete){
    integer pos = llListFindList(AGGRO, [player]);
    if(~pos){
        if(complete)AGGRO = llDeleteSubList(AGGRO, pos-1, pos+AGGRO_STRIDE-2);
        else AGGRO = llListReplaceList(AGGRO, [llList2Integer(AGGRO, pos+1)|AGFLAG_NOT_AGGROD], pos+1, pos+1);
    }
    aggro("",0);
}

float spdmtm(string spellName){
    if(!isset(spellName))return 1;
    integer i;
    for(i=0; i<llGetListLength(SPELL_DMG_TAKEN_MOD); i+=2){
        if(llList2String(SPELL_DMG_TAKEN_MOD, i) == spellName){
            float nr = llList2Float(SPELL_DMG_TAKEN_MOD, i+1);
            if(nr <0)return 0;
            return nr;
        }
    }
    return 1;
}

outputTextures(){
    string dta = mkarr(llList2ListStrided(SPELL_ICONS, 0, -1, SPSTRIDE));
    integer i;
    for(i=0; i<llGetListLength(OUTPUT_STATUS_TO); i++)
        GUI$setSpellTextures(llList2Key(OUTPUT_STATUS_TO, i), dta);
}

addHP(float amount, key attacker, string spellName){
    if(STATUS_FLAGS&StatusFlag$dead)return;
    float pre = HP;
    amount*=spdmtm(spellName);
    
    if(amount<0){
        amount*=fxModDmgTaken;
        if(attacker){
            aggro(attacker, llFabs(amount));
        }
    }
    
    HP += amount;
    if(HP<=0){
        HP = 0;
        STATUS_FLAGS = STATUS_FLAGS|StatusFlag$dead;
        raiseEvent(StatusEvt$dead, "1");
        MeshAnim$startAnim("die");
        outputStats();
        llSleep(.1);
        MeshAnim$stopAnim("idle");
        MeshAnim$stopAnim("walk");
        MeshAnim$stopAnim("attack");
        
        
        
        
        if(deathsound)llTriggerSound(deathsound, 1);
        if(~RUNTIME_FLAGS&Monster$RF_NO_DEATH){
            llSleep(2);
            llDie();
        }
    }else if(HP > maxHP)HP = maxHP;
    
    if(pre != HP)
        outputStats();
    
}

aggroCheck(key k, float mod){
    if(RUNTIME_FLAGS&Monster$RF_NOAGGRO)return;
    if(BFL&BFL_NOAGGRO)return;
    
    vector ppos = prPos(k);
    float dist =llVecDist(ppos, llGetPos()); 
    
    if(dist>100)return;
    
    integer ainfo = llGetAgentInfo(k);
    float range = aggro_range*mod;
    vector add = <0,0,1>;
    if(mod <= 1){
        list odata = llGetObjectDetails(k, [OBJECT_POS, OBJECT_ROT]);
        float bet = llRot2Angle(llRotBetween(llVecNorm(<0,0,1> * llGetRot()), llVecNorm(llList2Vector(odata, 0)-llGetPos())));
        if(bet>PI_BY_TWO)range*=.5;
        if(ainfo&AGENT_CROUCHING){
            add = ZERO_VECTOR;
            range *= .5;
            if(bet>PI_BY_TWO)range=.5;
        }
    }
    
    
    if(dist<range){
        list ray = llCastRay(llGetPos()+add, ppos+add, ([RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS]));
        if(llList2Integer(ray, -1) == 0){
            Status$get(k, "aggro");
        } 
    }
}




aggro(key player, float ag){
    if(BFL&BFL_NOAGGRO)return;
    
    if(player){
        integer pre = llGetListLength(AGGRO);
        player = llGetOwnerKey(player);
        integer pos = llListFindList(AGGRO, [player]);
        key top; integer i;
        if(~pos){
            float nr = llList2Float(AGGRO, pos-1);
            nr+=ag;
            if(nr<=0)dropAggro(player, TRUE);
            else{
                // Newly aggroed
                integer flag = llList2Integer(AGGRO, pos+1);
                if(flag&AGFLAG_NOT_AGGROD)
                    AGGRO = llListReplaceList(AGGRO, [flag&~AGFLAG_NOT_AGGROD], pos+1, pos+1);
                
                AGGRO = llListReplaceList(AGGRO, [nr], pos-1, pos-1);
            }
        }else if(ag>0)AGGRO += [ag, player, 0];
        
        if(AGGRO != [] && !pre)
            if(aggrosound)llTriggerSound(aggrosound, 1);
    }
    AGGRO = llListSort(AGGRO, AGGRO_STRIDE, FALSE);
    
    
    key at = "";
    integer i;
    for(i=0; i<llGetListLength(AGGRO); i+=AGGRO_STRIDE){
        if(~llList2Integer(AGGRO, i+2)&AGFLAG_NOT_AGGROD){
            at = llList2Key(AGGRO, i+1);
            i = llGetListLength(AGGRO);
        }
    }
    
    if(at != aggroTarg){
        aggroTarg = at;
        if(at == ""){
            if(dropaggrosound)
                llTriggerSound(dropaggrosound, 1);
        }else Root$targetMe(at, icon, FALSE);
        raiseEvent(StatusEvt$monster_gotTarget, mkarr([aggroTarg]));
    }
}

onEvt(string script, integer evt, string data){
    if(script == "got FXCompiler"){
        if(evt == FXCEvt$update){
            FXFLAGS = (integer)jVal(data, [0]);
            fxModDmgTaken = (float)jVal(data, [3]);
            fxModDmgDone = (float)jVal(data, [2]);
            outputStats();
        }
    }
    else if(script == "got LocalConf" && evt == LocalConfEvt$iniData){
        RUNTIME_FLAGS = (integer)j(data, MLC$RF);
        maxHP = (float)j(data, MLC$maxhp);
        aggro_range = (float)j(data, MLC$aggro_range);
        aggrosound = (key)j(data, MLC$aggro_sound);
        dropaggrosound = (key)j(data, MLC$dropaggro_sound);
        takehitsound = (key)j(data, MLC$takehit_sound);
        attacksound = (key)j(data, MLC$attacksound);
        deathsound = (key)j(data, MLC$deathsound);
        icon = (key)j(data, MLC$icon);
        dmg = (float)j(data, MLC$dmg);
        
        rapeName = j(data, MLC$rapePackage);
        if(!isset(rapeName))rapeName = llGetObjectName();
        
        if(dmg<=0)dmg = 10; 
        if(aggro_range<=0)aggro_range = 10;
        if(maxHP<=0)maxHP = 100;
        HP = maxHP;
    }else if(script == "got Portal" && evt == evt$SCRIPT_INIT){
        PLAYERS = llJson2List(data);
        multiTimer(["A", "", 1, TRUE]);
    }else if(script == "got Monster"){
        if(evt == MonsterEvt$runtimeFlagsChanged){
            RUNTIME_FLAGS = (integer)data;
        }else if(evt == MonsterEvt$attack){
            key targ = jVal(data, [0]);
            
            FX$send(targ, llGetKey(), "[1,0,0,0,[0,1,\"\",[[1,"+(string)(dmg*fxModDmgDone)+"],[3,"+(string)(dmg*.2*fxModDmgDone)+"],[6,\"<1,.5,.5>\"]],[],[],[],0,0,0]]");
            
        }else if(evt == MonsterEvt$attackStart){
            //qd("AttackStart");
            if(attacksound)
                llTriggerSound(attacksound, 1);
            
        }
    }
}

outputStats(){
    integer i;
    for(i=0; i<llGetListLength(OUTPUT_STATUS_TO); i++){
        GUI$status(llList2Key(OUTPUT_STATUS_TO, i), HP/maxHP, 0, 0, 0, STATUS_FLAGS, FXFLAGS);
    }
    
    raiseEvent(StatusEvt$flags, (string)STATUS_FLAGS);
    raiseEvent(StatusEvt$monster_hp_perc, (string)(HP/maxHP));
}


timerEvent(string id, string data){
    if(id == "A"){
        if(BFL&BFL_NOAGGRO)return;
        if(aggroTarg != ""){
            // Check the specific player instead
            Status$get(aggroTarg, "agc");
            return;
        }
        
        list p = PLAYERS;
        while(p){
            key k = llList2Key(p, 0);
            p = llDeleteSubList(p, 0, 0);
            aggroCheck(k, 1);
        }
    }else if(id == "OT"){
        outputTextures();
    }
}

default 
{
    on_rez(integer mew){
        llResetScript();
    }
    
    state_entry(){
        llSetStatus(STATUS_PHANTOM, TRUE);
        if(llGetStartParameter()){
            raiseEvent(evt$SCRIPT_INIT, "");
        }
    }
    
    touch_start(integer total){
        Root$targetMe(llDetectedKey(0), icon, TRUE);
    }
    
    timer(){multiTimer([]);}
    
    // This is the standard linkmessages
    #include "xobj_core/_LM.lsl" 
    /*
        Included in all these calls:
        METHOD - (int)method  
        PARAMS - (var)parameters 
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task 
    */ 
    
    // Here's where you receive callbacks from running methods
    if(method$isCallback){
        if(METHOD == StatusMethod$get && id!="" && SENDER_SCRIPT == "got Status"){
            if(CB == "aggro" || CB == "agc"){
                
                // agc checks if it should rape or not
                integer flags = (integer)method_arg(0);

                if(flags&(StatusFlag$raped|StatusFlag$dead)){
                    if(~flags&StatusFlag$raped){
                        Bridge$fetchRape(llGetOwnerKey(id), rapeName);
                    }
                    dropAggro(llGetOwnerKey(id), TRUE);
                    return;
                }
                if(flags&StatusFlag$raped)return;
                
                
                if(CB == "aggro")
                    aggro(llGetOwnerKey(id), 10);
                
                if(llGetOwnerKey(id) == aggroTarg)
                    raiseEvent(StatusEvt$monster_targData, PARAMS);
            } 
        }  
        return;
    }
    
    if(id == ""){
        if(METHOD == StatusMethod$addTextureDesc){
            key texture = (key)method_arg(0);
            string desc = method_arg(1);
            SPELL_ICONS += [texture, desc];
            multiTimer(["OT", "", .5, FALSE]);
        }
        else if(METHOD == StatusMethod$remTextureDesc){
            key texture = (key)method_arg(0);
            integer pos = llListFindList(SPELL_ICONS, [texture]);
            if(pos == -1)return;
            SPELL_ICONS = llDeleteSubList(SPELL_ICONS, pos, pos+SPSTRIDE-1);
            multiTimer(["OT", "", .1, FALSE]);
            
        }
    }
    
    if(method$byOwner){
        if(METHOD == StatusMethod$monster_setFlag){
            STATUS_FLAGS = STATUS_FLAGS|(integer)method_arg(0);
        }
        if(METHOD == StatusMethod$monster_remFlag){
            STATUS_FLAGS = STATUS_FLAGS&~(integer)method_arg(0);
        }
        if(METHOD == StatusMethod$addDurability)
            addHP((float)method_arg(0), method_arg(1), method_arg(2));
        
    }
    
    if(METHOD == StatusMethod$setTargeting){
        integer on = (integer)method_arg(0);
        integer pos = llListFindList(OUTPUT_STATUS_TO, [id]);
        if(!on){
            if(pos == -1)return;
            OUTPUT_STATUS_TO = llDeleteSubList(OUTPUT_STATUS_TO, pos, pos);
        }else{
            if(pos == -1)OUTPUT_STATUS_TO += id;
            outputStats();
            outputTextures();
        }
    }
    else if(METHOD == StatusMethod$get){
        CB_DATA = [STATUS_FLAGS, FXFLAGS, HP/maxHP, 0, 0, 0];
    }
    else if(METHOD == StatusMethod$monster_takehit){
        MeshAnim$startAnim("hit");
        if(takehitsound)llTriggerSound(takehitsound, 1);
    }
    else if(METHOD == StatusMethod$spellModifiers){
        SPELL_DMG_TAKEN_MOD = llJson2List(method_arg(0));
    }
    else if(METHOD == StatusMethod$getTextureDesc){
        if(id == "")id = llGetOwner();
        string out = "";
        
        integer pos = (integer)method_arg(0);
        string texture = method_arg(1);
        
        if(llList2String(SPELL_ICONS, pos*SPSTRIDE) == texture)out = llList2String(SPELL_ICONS, pos*SPSTRIDE+1);
        else{
            integer p = llListFindList(llList2ListStrided(SPELL_ICONS, 0, -1, SPSTRIDE), [(key)texture]);
            if(~p)out = llList2String(SPELL_ICONS, p*SPSTRIDE+1);
        }
        
        if(out)
            llRegionSayTo(llGetOwnerKey(id), 0, out);
    }
    else if(METHOD == StatusMethod$monster_dropAggro)
        dropAggro(method_arg(0), (integer)method_arg(1));
    else if(METHOD == StatusMethod$monster_attemptTarget)
        Root$targetMe(id, icon, FALSE);
    else if(METHOD == StatusMethod$monster_aggro)
        aggro(method_arg(0), (float)method_arg(1));
        
    // Public code can be put here

    // End link message code
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"  
}
