using System;
using BepInEx;
using HarmonyLib;
using PlayFab;
using PlayFab.ClientModels;
using Steamworks;

[BepInPlugin("onlinefix.valheim", "Valheim OnlineFix", "1.0.0")]
public sealed class OnlineFixPlugin : BaseUnityPlugin
{
    private void Awake()
    {
        new Harmony("onlinefix.valheim").PatchAll(typeof(LoginPatch));
        Logger.LogInfo("Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID");
    }
}

[HarmonyPatch(typeof(PlayFabClientAPI), "LoginWithSteam")]
internal static class LoginPatch
{
    private static bool Prefix(Action<LoginResult> resultCallback, Action<PlayFabError> errorCallback)
    {
        PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest
        {
            CreateAccount = true,
            CustomId = SteamUser.GetSteamID().ToString()
        }, resultCallback, errorCallback, null, null);
        return false;
    }
}
