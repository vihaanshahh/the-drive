using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace TheDrive.UnityGame.Editor
{
    public static class DriveBuild
    {
        private const string ScenePath = "Assets/Scenes/TheDrive.unity";
        private const string AppID = "com.vihaanshah.thedrive.unity";

        [MenuItem("The Drive/Prepare Project")]
        public static void Prepare()
        {
            PlayerSettings.companyName = "Vihaan Shah";
            PlayerSettings.productName = "The Drive Unity";
            PlayerSettings.bundleVersion = "0.1.0";
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, AppID);
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
            PlayerSettings.iOS.targetOSVersionString = "17.0";
            PlayerSettings.iOS.appleDeveloperTeamID = "R3BHK7TDH8";
            PlayerSettings.iOS.appleEnableAutomaticSigning = true;
            PlayerSettings.iOS.buildNumber = "1";
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.defaultScreenWidth = 1280;
            PlayerSettings.defaultScreenHeight = 720;
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.runInBackground = false;
            PlayerSettings.SplashScreen.show = false;
            var icon = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/TheDrive/Resources/Drive/Art/AppIcon.png");
            if (icon) PlayerSettings.SetIcons(NamedBuildTarget.iOS, new[] { icon }, IconKind.Any);
            var launch = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/TheDrive/Resources/Drive/Art/LaunchArtwork.png");
            if (launch)
            {
                PlayerSettings.iOS.SetiPhoneLaunchScreenType(iOSLaunchScreenType.ImageAndBackgroundRelative);
                PlayerSettings.iOS.SetiPadLaunchScreenType(iOSLaunchScreenType.ImageAndBackgroundRelative);
                PlayerSettings.iOS.SetLaunchScreenImage(launch, iOSLaunchScreenImageType.iPhoneLandscapeImage);
                PlayerSettings.iOS.SetLaunchScreenImage(launch, iOSLaunchScreenImageType.iPhonePortraitImage);
                PlayerSettings.iOS.SetLaunchScreenImage(launch, iOSLaunchScreenImageType.iPadImage);
            }
            PlayerSettings.iOS.showActivityIndicatorOnLoading = iOSShowActivityIndicatorOnLoading.Medium;
            Directory.CreateDirectory("Assets/Scenes");
            if (!File.Exists(ScenePath))
            {
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            // A real material asset keeps the Standard shader available to runtime-created source materials.
            const string standardPath = "Assets/TheDrive/Resources/Drive/Standard.mat";
            if (!File.Exists(standardPath))
            {
                var shader = Shader.Find("Standard");
                if (!shader) throw new InvalidOperationException("Built-in Standard shader is unavailable.");
                AssetDatabase.CreateAsset(new Material(shader), standardPath);
            }
            AssetDatabase.SaveAssets();
            Debug.Log("The Drive Unity project ready. iOS app ID: " + AppID);
        }

        [MenuItem("The Drive/Build iPhone")]
        public static void BuildIOS()
        {
            Prepare();
            string output = Environment.GetEnvironmentVariable("THE_DRIVE_UNITY_IOS_OUTPUT");
            if (string.IsNullOrEmpty(output)) output = Path.GetFullPath("Builds/iOS");
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = output,
                target = BuildTarget.iOS,
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException("Unity iOS export failed: " + report.summary.result);
            Debug.Log("The Drive Unity Xcode project: " + output);
        }

        [MenuItem("The Drive/Build Mac Preview")]
        public static void BuildMac()
        {
            Prepare();
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = Path.GetFullPath("Builds/TheDriveUnity.app"),
                target = BuildTarget.StandaloneOSX,
                options = BuildOptions.Development
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException("Unity Mac preview build failed: " + report.summary.result);
        }
    }
}
