using System;
using System.IO;
using System.Security.Cryptography;
using BepInEx;
using HarmonyLib;
using PlayFab;
using PlayFab.ClientModels;
using Steamworks;

[BepInPlugin("onlinefix.valheim", "Valheim OnlineFix", "1.1.0")]
public sealed class OnlineFixPlugin : BaseUnityPlugin
{
    private const string StockPlayFabHash = "88e39787d1b66b64c0a89514b4a6d635659f9198c41146c5ecab303213f9eae6";

    private void Awake()
    {
        new Harmony("onlinefix.valheim").PatchAll(typeof(LoginPatch));
        Logger.LogInfo("Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID");
        CheckPlayFabAssembly();
    }

    private void CheckPlayFabAssembly()
    {
        try
        {
            string path = typeof(PlayFabClientAPI).Assembly.Location;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                Logger.LogWarning("PlayFab assembly path is not a file: " + path);
                return;
            }
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
            {
                string hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
                if (hash != StockPlayFabHash)
                    Logger.LogWarning($"PlayFab.dll is not stock ({path}, sha256={hash}). A patched PlayFab can throw InvalidProgramException; restore it from PlayFab.dll.onlinefix-valheim-backup.");
                else
                    Logger.LogInfo("PlayFab.dll hash is stock");
            }
        }
        catch (Exception e)
        {
            Logger.LogWarning("PlayFab integrity check failed: " + e.Message);
        }
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
