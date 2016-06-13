#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <addicted>

#pragma semicolon 1

public Plugin myinfo = 
{
	name = "Jail: Team Ratio",
	author = "Addicted",
	version = "1.0",
	url = "oaaron.com"
};

Handle g_aGuardQueue;
Handle cookie_ct_banned;
Handle cvar_prisoners_per_guard;

char g_szRestrictedSound[] = "buttons/button11.wav";

public void OnPluginStart()
{
	cvar_prisoners_per_guard = CreateConVar("jb_prisoners_per_guard", "2", "How many prisoners for each guard.", _, true, 1.0);
	
	if((cookie_ct_banned = FindClientCookie("Banned_From_CT")) == INVALID_HANDLE)
		cookie_ct_banned = RegClientCookie("Banned_From_CT", "Tells if you are restricted from joining the CT team", CookieAccess_Protected);
	
	g_aGuardQueue = CreateArray();
	
	AddCommandListener(OnJoinTeam, "jointeam");
	HookEvent("player_team", Event_PlayerTeam_Post, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd_Post, EventHookMode_Post);
	HookEvent("player_spawn", Event_OnPlayerSpawn, EventHookMode_Post);
	
	RegConsoleCmd("sm_guard", OnGuardQueue);
	RegConsoleCmd("sm_viewqueue", ViewGuardQueue);
	RegConsoleCmd("sm_vq", ViewGuardQueue);
}

public void OnConfigsExecuted()
{
	Handle hConVar = FindConVar("mp_force_pick_time");
	if(hConVar == INVALID_HANDLE)
		return;
	
	HookConVarChange(hConVar, OnForcePickTimeChanged);
	SetConVarInt(hConVar, 999999);
}

public void OnForcePickTimeChanged(Handle hConVar, const char[] szOldValue, const char[] szNewValue)
{
	SetConVarInt(hConVar, 999999);
}

public void OnClientDisconnect_Post(int client)
{
	RemovePlayerFromGuardQueue(client);
}

public Action Event_OnPlayerSpawn(Event event, const char[] name, bool bDontBroadcast) 
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (GetClientTeam(client) != 3) 
		return Plugin_Continue;
		
	if (!IsValidClient(client))
		return Plugin_Continue;
		
	char sData[2];
	GetClientCookie(client, cookie_ct_banned, sData, sizeof(sData));
	
	if(sData[0] == '1')
	{
		PrintToChatAndConsole(client, "[{blue}Teams{default}] Cannot play on guards because you are CT banned.");
		PrintHintText(client, "Cannot play on guards because you are CT banned.");
		CreateTimer(5.0, SlayPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

public Action SlayPlayer(Handle hTimer, any iUserId) 
{
	int client = GetClientOfUserId(iUserId);
	
	if (!IsValidClient(client))
		return Plugin_Stop;
		
	if (!IsPlayerAlive(client)) 
		return Plugin_Stop;
		
	if (GetClientTeam(client) != 3) 
		return Plugin_Stop;

	ForcePlayerSuicide(client);
	ChangeClientTeam(client, 2);
	CS_RespawnPlayer(client);
	
	return Plugin_Stop;
}

public void Event_PlayerTeam_Post(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	if(GetEventInt(hEvent, "team") != 3)
		return;
	
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	RemovePlayerFromGuardQueue(client);
}

public Action Event_RoundEnd_Post(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	FixTeamRatio();
}

public Action OnJoinTeam(int client, const char[] szCommand, int iArgCount)
{
	if(iArgCount < 1)
		return Plugin_Continue;
	
	char szData[2];
	GetCmdArg(1, szData, sizeof(szData));
	int iTeam = StringToInt(szData);
	
	if(!iTeam)
	{
		ClientCommand(client, "play %s", g_szRestrictedSound);
		PrintToChatAndConsole(client, "[{blue}Teams{default}] You cannot use auto select to join a team.");
		return Plugin_Handled;
	}
	
	if(iTeam != CS_TEAM_CT)
		return Plugin_Continue;
	
	GetClientCookie(client, cookie_ct_banned, szData, sizeof(szData));
	
	if(szData[0] == '1')
	{
		ClientCommand(client, "play %s", g_szRestrictedSound);
		PrintToChatAndConsole(client, "[{blue}Teams{default}] Cannot join guards because you are CT banned.");
		FakeClientCommand(client, "sm_isbanned @me");
		return Plugin_Handled;
	}

	if(!CanClientJoinGuards(client))
	{
		int iIndex = FindValueInArray(g_aGuardQueue, client);
		
		if(iIndex == -1)
			PrintToChatAndConsole(client, "[{blue}Teams{default}] Guards team full. Type !guard to join the queue.");
		else
			PrintToChatAndConsole(client, "[{blue}Teams{default}] Guards team full. You are {green}#%i{default} in the queue.", iIndex + 1);
		
		ClientCommand(client, "play %s", g_szRestrictedSound);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action ViewGuardQueue(int client, int args)
{
	if(!IsValidClient(client))
		return Plugin_Handled;

	if(GetArraySize(g_aGuardQueue) < 1)
	{
		PrintToChatAndConsole(client, "[{blue}Teams{default}] The queue is currently empty.");
		return Plugin_Handled;
	}
	
	Handle hMenu = CreateMenu(ViewQueueMenuHandle);
	SetMenuTitle(hMenu, "Guard Queue:");

	for (int i; i < GetArraySize(g_aGuardQueue); i++)
	{
		if(!IsValidClient(GetArrayCell(g_aGuardQueue, i)))
			continue;

		char display[120];
		Format(STRING(display), "%N", GetArrayCell(g_aGuardQueue, i));
		AddMenuItem(hMenu, "", display);
	}
	
	DisplayMenu(hMenu, client, 0);
	
	return Plugin_Handled;
}

public int ViewQueueMenuHandle(Handle menu, MenuAction action, int client, int option)
{
	if (action == MenuAction_End)
	{
		CloneHandle(menu);
	}
}

public Action OnGuardQueue(int client, int iArgNum)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}
	
	if(GetClientTeam(client) != CS_TEAM_T)
	{
		ClientCommand(client, "play %s", g_szRestrictedSound);
		PrintToChatAndConsole(client, "[{blue}Teams{default}] You must be a prisoner to join the queue.");
		return Plugin_Handled;
	}
	
	char szCookie[2];
	GetClientCookie(client, cookie_ct_banned, szCookie, sizeof(szCookie));
	if(szCookie[0] == '1')
	{
		ClientCommand(client, "play %s", g_szRestrictedSound);
		PrintToChatAndConsole(client, "[{blue}Teams{default}] Cannot join guards because you are CT banned.");
		FakeClientCommand(client, "sm_isbanned @me");
		return Plugin_Handled;
	}
	
	int iIndex = FindValueInArray(g_aGuardQueue, client);
	int iQueueSize = GetArraySize(g_aGuardQueue);
	
	if(iIndex == -1)
	{
		if (CheckCommandAccess(client, "", ADMFLAG_RESERVATION, true))
		{
			if (iQueueSize == 0)
				iIndex = PushArrayCell(g_aGuardQueue, client);
			else
			{
				ShiftArrayUp(g_aGuardQueue, 0);
				SetArrayCell(g_aGuardQueue, 0, client);
			}

			PrintToChatAndConsole(client, "[{blue}Teams{default}] Thank you for being a {darkred}VIP{default}! You have been moved to the {green}front of the queue!{default}");
			PrintToChatAndConsole(client, "[{blue}Teams{default}] You are {green}#1{default} in the guard queue.");
			PrintToChatAndConsole(client, "[{blue}Teams{default}] Type !viewqueue to see who else is in the queue.");
			return Plugin_Handled;
		}
		else
		{
			iIndex = PushArrayCell(g_aGuardQueue, client);
			
			PrintToChatAndConsole(client, "[{blue}Teams{default}] You are {green}#%i{default} in the guard queue.", iIndex + 1);
			PrintToChatAndConsole(client, "[{blue}Teams{default}] Get {darkred}VIP{default} to be automatically moved to the front of the queue.");
			PrintToChatAndConsole(client, "[{blue}Teams{default}] Type !viewqueue to see who else is in the queue.");
			
			return Plugin_Handled;
		}
	}
	else
	{
		PrintToChatAndConsole(client, "[{blue}Teams{default}] You are {green}#%i{default} in the guard queue.", iIndex + 1);
		PrintToChatAndConsole(client, "[{blue}Teams{default}] Get {darkred}VIP{default} to be automatically moved to the front of the queue.");
		PrintToChatAndConsole(client, "[{blue}Teams{default}] Type !viewqueue to see who else is in the queue.");
	}
	return Plugin_Continue;
}

stock bool RemovePlayerFromGuardQueue(int client)
{
	int iIndex = FindValueInArray(g_aGuardQueue, client);
	if(iIndex == -1)
		return;
	
	RemoveFromArray(g_aGuardQueue, iIndex);
}

stock void FixTeamRatio()
{
	bool bMovedPlayers;
	while(ShouldMovePrisonerToGuard())
	{
		int client;
		if(GetArraySize(g_aGuardQueue))
		{
			client = GetArrayCell(g_aGuardQueue, 0);
			RemovePlayerFromGuardQueue(client);
			
			PrintToChatAndConsoleAll("[{blue}Teams{default}] Finding a new guard from queue. Found %N.", client);
		}
		else
		{
			client = GetRandomClientFromTeam(CS_TEAM_T, true);
			PrintToChatAndConsoleAll("[{blue}Teams{default}] Guard queue is empty. Finding a random new guard. Found %N.", client);
		}
		
		if(!IsValidClient(client))
		{
			PrintToChatAndConsoleAll("[{blue}Teams{default}] Could not find a valid player to switch to guards. Ratio may be fucked.");
			break;
		}
		
		SetClientPendingTeam(client, CS_TEAM_CT);
		bMovedPlayers = true;
	}
	
	if(bMovedPlayers)
		return;
	
	while(ShouldMoveGuardToPrisoner())
	{
		int client = GetRandomClientFromTeam(CS_TEAM_CT, true);
		if(!client)
			break;
		
		SetClientPendingTeam(client, CS_TEAM_T);
	}
}

stock int GetRandomClientFromTeam(int iTeam, bool bSkipCTBanned=true)
{
	int iNumFound;
	int clients[MAXPLAYERS];
	char szCookie[2];

	LoopValidPlayers(i)
	{
		if(!IsClientInGame(i))
			continue;

		if(GetClientPendingTeam(i) != iTeam)
			continue;

		if(bSkipCTBanned)
		{
			if(!AreClientCookiesCached(i))
				continue;
			
			GetClientCookie(i, cookie_ct_banned, szCookie, sizeof(szCookie));
			if(szCookie[0] == '1')
				continue;
		}

		clients[iNumFound++] = i;
	}

	if(!iNumFound)
		return 0;

	return clients[GetRandomInt(0, iNumFound-1)];
}

bool ShouldMoveGuardToPrisoner()
{
	int iNumGuards, iNumPrisoners;
	
	LoopValidPlayers(i)
	{	
		if (GetClientPendingTeam(i) == 2)
			iNumPrisoners++;
		else if (GetClientPendingTeam(i) == 3)
			 iNumGuards++;
	}

	if(iNumGuards <= 1)
		return false;

	if(iNumGuards <= RoundToFloor(float(iNumPrisoners) / GetConVarFloat(cvar_prisoners_per_guard)))
		return false;

	return true;
}

bool ShouldMovePrisonerToGuard()
{
	int iNumGuards, iNumPrisoners;
	
	LoopValidPlayers(i)
	{	
		if (GetClientPendingTeam(i) == 2)
			iNumPrisoners++;
		else if (GetClientPendingTeam(i) == 3)
			 iNumGuards++;
	}
	
	iNumPrisoners--;
	iNumGuards++;
	
	if(iNumPrisoners < 1)
		return false;

	if(float(iNumPrisoners) / float(iNumGuards) < GetConVarFloat(cvar_prisoners_per_guard))
		return false;
	
	return true;
}

stock bool CanClientJoinGuards(int client)
{
	int iNumGuards, iNumPrisoners;
	
	LoopValidPlayers(i)
	{	
		if (GetClientPendingTeam(i) == 2)
			iNumPrisoners++;
		else if (GetClientPendingTeam(i) == 3)
			 iNumGuards++;
	}
	
	iNumGuards++;
	if(GetClientPendingTeam(client) == CS_TEAM_T)
		iNumPrisoners--;
	
	if(iNumGuards <= 1)
		return true;
	
	float fNumPrisonersPerGuard = float(iNumPrisoners) / float(iNumGuards);
	if(fNumPrisonersPerGuard < GetConVarFloat(cvar_prisoners_per_guard))
		return false;
	
	int iGuardsNeeded = RoundToCeil(fNumPrisonersPerGuard - GetConVarFloat(cvar_prisoners_per_guard));
	if(iGuardsNeeded < 1)
		iGuardsNeeded = 1;
	
	int iQueueSize = GetArraySize(g_aGuardQueue);
	if(iGuardsNeeded > iQueueSize)
		return true;
	
	for(int i; i < iGuardsNeeded; i++)
	{
		if (!IsValidClient(i))
			continue;
		
		if(client == GetArrayCell(g_aGuardQueue, i))
			return true;
	}
	
	return false;
}

stock int GetClientPendingTeam(int client)
{
	return GetEntProp(client, Prop_Send, "m_iPendingTeamNum");
}

stock void SetClientPendingTeam(int client, int iTeam)
{
	SetEntProp(client, Prop_Send, "m_iPendingTeamNum", iTeam);
}