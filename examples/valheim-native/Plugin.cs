using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using HarmonyLib;
using PlayFab;
using PlayFab.ClientModels;
using Steamworks;

[BepInPlugin("onlinefix.valheim", "Valheim OnlineFix", "1.3.0")]
public sealed class OnlineFixPlugin : BaseUnityPlugin
{
    private const string StockPlayFabHash = "88e39787d1b66b64c0a89514b4a6d635659f9198c41146c5ecab303213f9eae6";

    internal static ConfigEntry<bool> CrossplayOnly;
    internal static ManualLogSource Log;

    private void Awake()
    {
        Log = Logger;
        CrossplayOnly = Config.Bind("Server browser", "CrossplayOnly", true,
            "Hide the Steam AppID 480 server list (other OnlineFix games and fake-app servers). Only PlayFab/crossplay Valheim servers are shown.");
        var harmony = new Harmony("onlinefix.valheim");
        var login = AccessTools.Method(typeof(PlayFabClientAPI), "LoginWithSteam", new[]
        {
            typeof(LoginWithSteamRequest), typeof(Action<LoginResult>), typeof(Action<PlayFabError>), typeof(object), typeof(Dictionary<string, string>)
        });
        if (login == null)
        {
            Logger.LogError("LoginWithSteam not found; online login will fail");
        }
        else
        {
            harmony.Patch(login, new HarmonyMethod(typeof(LoginPatch), nameof(LoginPatch.Prefix)));
            Logger.LogInfo("patched " + login.DeclaringType?.FullName + "." + login.Name);
        }
        var loadAppId = AccessTools.Method(typeof(SteamManager), "LoadAPPID");
        if (loadAppId != null)
        {
            harmony.Patch(loadAppId, prefix: new HarmonyMethod(typeof(AppIdPatch), nameof(AppIdPatch.Prefix)));
            Logger.LogInfo("patched SteamManager.LoadAPPID");
        }
        var restart = AccessTools.Method(typeof(SteamAPI), "RestartAppIfNecessary");
        if (restart != null)
        {
            harmony.Patch(restart, prefix: new HarmonyMethod(typeof(RestartPatch), nameof(RestartPatch.Prefix)));
            Logger.LogInfo("patched SteamAPI.RestartAppIfNecessary");
        }
        var authLogin = AccessTools.Method(typeof(PlayFabAuthWithSteam), "Login");
        if (authLogin != null)
        {
            harmony.Patch(authLogin, prefix: new HarmonyMethod(typeof(AuthPatch), nameof(AuthPatch.Prefix)));
            Logger.LogInfo("patched PlayFabAuthWithSteam.Login");
        }
        var constructor = AccessTools.Constructor(typeof(MultiBackendMatchmaking));
        if (constructor != null)
        {
            harmony.Patch(constructor, postfix: new HarmonyMethod(typeof(CrossplayOnlyPatch), nameof(CrossplayOnlyPatch.Postfix)));
            Logger.LogInfo("patched MultiBackendMatchmaking constructor");
        }
        Logger.LogInfo("Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID");
        Logger.LogInfo("Valheim OnlineFix: crossplay-only browser = " + CrossplayOnly.Value);
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
    internal static bool Prefix(Action<LoginResult> resultCallback, Action<PlayFabError> errorCallback)
    {
        PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest
        {
            CreateAccount = true,
            CustomId = SteamUser.GetSteamID().ToString()
        }, resultCallback, errorCallback, null, null);
        return false;
    }
}

internal static class AppIdPatch
{
    internal static bool Prefix(ref uint __result)
    {
        __result = 892970u;
        return false;
    }
}

internal static class RestartPatch
{
    internal static bool Prefix(ref bool __result)
    {
        __result = false;
        return false;
    }
}

internal static class AuthPatch
{
    internal static bool Prefix()
    {
        var success = (Action<LoginResult>)Delegate.CreateDelegate(typeof(Action<LoginResult>),
            AccessTools.Method(typeof(PlayFabAuthWithSteam), "OnSteamLoginSuccess"));
        var failure = (Action<PlayFabError>)Delegate.CreateDelegate(typeof(Action<PlayFabError>),
            AccessTools.Method(typeof(PlayFabAuthWithSteam), "OnSteamLoginFailed"));
        PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest
        {
            CreateAccount = true,
            CustomId = SteamUser.GetSteamID().ToString()
        }, success, failure, null, null);
        return false;
    }
}

[HarmonyPatch(typeof(MultiBackendMatchmaking), MethodType.Constructor)]
internal static class CrossplayOnlyPatch
{
    internal static void Postfix(MultiBackendMatchmaking __instance)
    {
        if (!OnlineFixPlugin.CrossplayOnly.Value) return;
        var field = AccessTools.Field(typeof(MultiBackendMatchmaking), "m_backends");
        if (field?.GetValue(__instance) is List<IMatchmakingBackend> backends)
        {
            backends.RemoveAll(b => b is SteamworksMatchmaking);
            OnlineFixPlugin.Log?.LogInfo("Server browser: Steam-480 list hidden, showing PlayFab/crossplay only");
        }
    }
}
