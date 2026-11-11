#if DEVELOPMENT_BUILD || UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace TheDrive.UnityGame
{
    /// <summary>Opt-in local player smoke run; never enabled during ordinary play.</summary>
    public sealed class DriveSmoke : MonoBehaviour
    {
        private string directory;
        private int errors;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Boot()
        {
            var args = Environment.GetCommandLineArgs();
            int option = Array.IndexOf(args, "-driveSmoke");
            if (option < 0) return;
            var smoke = new GameObject("Local smoke verification").AddComponent<DriveSmoke>();
            smoke.directory = option + 1 < args.Length ? args[option + 1] : Path.Combine(Application.persistentDataPath, "Smoke");
        }

        private IEnumerator Start()
        {
            Application.logMessageReceived += OnLog;
            Directory.CreateDirectory(directory);
            float deadline = Time.realtimeSinceStartup + 20;
            while (DriveGame.Instance == null && Time.realtimeSinceStartup < deadline) yield return null;
            if (DriveGame.Instance == null)
            {
                File.WriteAllText(Path.Combine(directory, "result.json"), "{\"passed\":false,\"errors\":1,\"reason\":\"Game startup timed out\"}");
                Application.Quit(1);
                yield break;
            }
            var game = DriveGame.Instance;
            yield return new WaitForSeconds(1);
            yield return Capture("market.png");
            if (!Tap("Start")) errors++;
            yield return new WaitForSeconds(2);
            double before = game.Distance;
            var pointer = new PointerEventData(EventSystem.current) { pointerId = 17 };
            var left = FindFirstObjectByType<HoldControl>();
            if (left == null) errors++;
            else
            {
                left.OnPointerDown(pointer);
                yield return new WaitForSeconds(.3f);
                left.OnPointerUp(pointer);
            }
            yield return new WaitForSeconds(.4f);
            if (!game.Running || game.Distance <= before || !double.IsFinite(game.SpeedKPH)) errors++;
            yield return Capture("driving.png");
            if (left != null) left.OnPointerDown(pointer);
            if (!Tap("Pause")) errors++;
            if (left != null && left.IsHeld) errors++;
            double paused = game.Distance;
            yield return new WaitForSeconds(.4f);
            if (game.Distance != paused) errors++;
            if (!Tap("RESUME")) errors++;
            if (left != null)
            {
                var nextPointer = new PointerEventData(EventSystem.current) { pointerId = 18 };
                left.OnPointerDown(nextPointer);
                if (!left.IsHeld) errors++;
                left.OnPointerUp(nextPointer);
            }
            yield return new WaitForSeconds(.4f);
            if (game.Distance <= paused) errors++;
            File.WriteAllText(Path.Combine(directory, "result.json"),
                "{\"passed\":" + (errors == 0 ? "true" : "false") + ",\"errors\":" + errors
                + ",\"distance\":" + game.Distance.ToString(System.Globalization.CultureInfo.InvariantCulture)
                + ",\"speedKPH\":" + game.SpeedKPH.ToString(System.Globalization.CultureInfo.InvariantCulture) + "}");
            Debug.Log("THE_DRIVE_SMOKE " + (errors == 0 ? "PASSED" : "FAILED"));
            yield return new WaitForSeconds(.25f);
            Application.Quit(errors == 0 ? 0 : 1);
        }

        private IEnumerator Capture(string name)
        {
            yield return new WaitForEndOfFrame();
            ScreenCapture.CaptureScreenshot(Path.Combine(directory, name));
            yield return null;
        }

        private bool Tap(string name)
        {
            Canvas.ForceUpdateCanvases();
            Button button = null;
            foreach (var candidate in FindObjectsByType<Button>(FindObjectsSortMode.None))
                if (candidate.name == name) { button = candidate; break; }
            if (button == null || !button.IsInteractable()) return false;
            var rect = button.GetComponent<RectTransform>();
            var pointer = new PointerEventData(EventSystem.current)
            {
                pointerId = -1,
                button = PointerEventData.InputButton.Left,
                position = RectTransformUtility.WorldToScreenPoint(null, rect.TransformPoint(rect.rect.center))
            };
            var hits = new List<RaycastResult>();
            EventSystem.current.RaycastAll(pointer, hits);
            if (hits.Count == 0 || hits[0].gameObject != button.gameObject) return false;
            ExecuteEvents.Execute(button.gameObject, pointer, ExecuteEvents.pointerDownHandler);
            ExecuteEvents.Execute(button.gameObject, pointer, ExecuteEvents.pointerUpHandler);
            ExecuteEvents.Execute(button.gameObject, pointer, ExecuteEvents.pointerClickHandler);
            return true;
        }

        private void OnLog(string text, string stack, LogType type)
        {
            if (type == LogType.Exception || type == LogType.Error || type == LogType.Assert) errors++;
        }
        private void OnDestroy() { Application.logMessageReceived -= OnLog; }
    }
}
#endif
