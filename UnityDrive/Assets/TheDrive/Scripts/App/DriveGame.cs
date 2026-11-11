using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace TheDrive.UnityGame
{
    /// <summary>First Unity driving milestone: real source assets, seeded endless road and mobile controls.</summary>
    public sealed class DriveGame : MonoBehaviour
    {
        public static DriveGame Instance { get; private set; }
        public double Distance { get; private set; }
        public double SpeedKPH { get; private set; } = 72;
        public ulong Seed { get; private set; }
        public bool Running { get; private set; }
        public int Cash => (int)(Distance / 10);
        private GameObject jeep;
        private EndlessRoad road;
        private Camera chase;
        private RoadSuspension suspension = new RoadSuspension();
        private double velocity = 20;
        private float lane, targetLane, previewClock, health = 1;
        private bool leftHeld, rightHeld, userPaused, backgrounded, finished;
        private readonly List<HoldControl> holdControls = new List<HoldControl>();
        private Canvas canvas;
        private RectTransform safeArea;
        private Rect safeRect;
        private GameObject menu, controls, pausePanel, hudPanel;
        private Text distanceText, speedText, cashText, seedText, healthText, resultText;
        private Font font;
        private readonly List<Hazard> hazards = new List<Hazard>();
        private SeededRandom random;
        private double nextHazard = 150;
        private int dodgeCount;
        private Material hazardMaterial;
        private static readonly Color Sand = new Color(.96f, .78f, .48f);

        private sealed class Hazard
        {
            public GameObject Root;
            public double Distance;
            public float Lane;
            public bool Resolved;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Boot()
        {
            if (FindAnyObjectByType<DriveGame>() == null)
                new GameObject("The Drive").AddComponent<DriveGame>();
        }

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 0;
            Screen.orientation = ScreenOrientation.LandscapeLeft;
            font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            ConfigureLighting();
            road = new GameObject("Seeded endless world").AddComponent<EndlessRoad>();
            jeep = DriveAssets.CreateJeep();
            chase = new GameObject("Chase camera").AddComponent<Camera>();
            chase.fieldOfView = 61;
            chase.nearClipPlane = .15f;
            chase.farClipPlane = 320;
            chase.allowHDR = true;
            chase.backgroundColor = new Color(.68f, .50f, .34f);
            chase.clearFlags = CameraClearFlags.SolidColor;
            chase.gameObject.AddComponent<AudioListener>();
            hazardMaterial = new Material(Shader.Find("Standard")) { color = new Color(.55f, .22f, .12f) };
            for (int i = 0; i < 7; i++)
            {
                var obstacle = GameObject.CreatePrimitive(PrimitiveType.Cube);
                obstacle.name = "Road barrier " + i;
                obstacle.transform.localScale = new Vector3(1.6f, .8f, .7f);
                obstacle.GetComponent<Renderer>().sharedMaterial = hazardMaterial;
                Destroy(obstacle.GetComponent<Collider>());
                obstacle.SetActive(false);
                hazards.Add(new Hazard { Root = obstacle });
            }
            MakeInterface();
            NewRoute();
        }

        private void ConfigureLighting()
        {
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(.75f, .71f, .61f);
            RenderSettings.ambientEquatorColor = new Color(.48f, .40f, .31f);
            RenderSettings.ambientGroundColor = new Color(.25f, .20f, .16f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogStartDistance = 100;
            RenderSettings.fogEndDistance = 290;
            RenderSettings.fogColor = new Color(.68f, .50f, .34f);
            var sun = new GameObject("Late afternoon sun").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = new Color(1, .83f, .61f);
            sun.intensity = 1.2f;
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(40, -30, 0);
            RenderSettings.sun = sun;
            QualitySettings.shadowDistance = 65;
        }

        public void NewRoute()
        {
            Seed = unchecked((ulong)DateTime.UtcNow.Ticks ^ 0xD351BA2AA7UL);
            random = new SeededRandom(Seed);
            Distance = 0; velocity = 20; SpeedKPH = 72;
            lane = targetLane = previewClock = 0; health = 1; dodgeCount = 0;
            finished = false;
            CancelSteering();
            nextHazard = 150; leftHeld = rightHeld = userPaused = false;
            road.Reset(Seed);
            suspension.Reset(RoadSurface.Sample(0, 0, Seed));
            foreach (var hazard in hazards) hazard.Root.SetActive(false);
            Running = false;
            resultText.text = "A quiet bazaar. An old Jeep.\nA long way out.";
            seedText.text = "ROUTE " + Seed.ToString("X");
            menu.SetActive(true); controls.SetActive(false); pausePanel.SetActive(false); hudPanel.SetActive(false);
            PlaceJeep(0, .016f);
            UpdateCamera(true);
            UpdateHUD();
        }

        public void StartRun()
        {
            if (Running) return;
            if (finished) NewRoute();
            Running = true;
            previewClock = 0;
            menu.SetActive(false); controls.SetActive(true); hudPanel.SetActive(true);
            targetLane = lane;
        }

        public void SetPaused(bool value)
        {
            userPaused = value;
            CancelSteering();
            pausePanel.SetActive(value && Running);
        }

        private void Update()
        {
            UpdateSafeArea();
            if (backgrounded || userPaused) return;
            float dt = Mathf.Min(Time.deltaTime, .05f);
            if (dt <= 0) return;
            if (!Running)
            {
                previewClock += dt;
                DriveAssets.AnimateJeep(jeep, previewClock * 3, Mathf.Sin(previewClock * .3f) * .08f);
                DriveAssets.PoseDriver(jeep, 0, previewClock);
                UpdateCamera(true);
                return;
            }
            float input = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0);
            input += Input.GetAxisRaw("Horizontal");
            if (Input.GetKeyDown(KeyCode.Escape)) SetPaused(true);
            targetLane = Mathf.Clamp(targetLane + Mathf.Clamp(input, -1, 1) * dt * 8, -4.1f, 4.1f);
            float previousX = lane;
            lane = Mathf.Lerp(lane, targetLane, 1 - Mathf.Exp(-dt * 10));
            var pace = DrivingPace.Sample(Distance, Seed);
            velocity = DrivingPace.FilteredVelocity(velocity, pace.TargetKPH / 3.6, dt);
            float step = (float)(velocity * dt);
            Distance += step; SpeedKPH = velocity * 3.6;
            road.Advance(step, Distance);
            PlaceJeep((lane - previousX) / Mathf.Max(dt, .001f) / 8, dt);
            UpdateHazards();
            UpdateCamera(false);
            UpdateHUD();
        }

        private void PlaceJeep(float steering, float dt)
        {
            var sample = suspension.Update(RoadSurface.Sample(Distance, lane, Seed), dt);
            jeep.transform.position = new Vector3(lane, sample.Height, 0);
            jeep.transform.rotation = Quaternion.Euler(sample.Pitch * Mathf.Rad2Deg, -steering * 3, sample.Roll * Mathf.Rad2Deg - steering * 2);
            DriveAssets.AnimateJeep(jeep, (float)Distance, steering);
            DriveAssets.PoseDriver(jeep, 0, (float)(Distance / 20));
        }

        private void UpdateCamera(bool preview)
        {
            Vector3 desired = preview
                ? jeep.transform.position + new Vector3(7.6f + Mathf.Sin(previewClock * .14f) * .4f, 4.9f, 8.8f)
                : jeep.transform.position + new Vector3(1.15f, 3.8f, 7.2f);
            chase.transform.position = preview ? desired : Vector3.Lerp(chase.transform.position, desired, 1 - Mathf.Exp(-Time.deltaTime * 9));
            chase.transform.LookAt(new Vector3(lane * .6f, RoadSurface.Height(Distance + 15, lane, Seed) + 1, preview ? -5 : -16));
        }

        private void UpdateHazards()
        {
            if (Distance >= nextHazard)
            {
                foreach (var hazard in hazards) if (!hazard.Root.activeSelf)
                {
                    hazard.Distance = Distance + DrivingPace.HazardLead(velocity);
                    hazard.Lane = random.Range(-1, 2) * 3.2f;
                    hazard.Resolved = false;
                    hazard.Root.SetActive(true);
                    break;
                }
                nextHazard = Distance + random.Range(45, 75);
            }
            foreach (var hazard in hazards) if (hazard.Root.activeSelf)
            {
                float z = (float)(Distance - hazard.Distance);
                hazard.Root.transform.position = new Vector3(hazard.Lane, RoadSurface.Height(hazard.Distance, hazard.Lane, Seed) + .4f, z);
                if (!hazard.Resolved && z >= -1.3f)
                {
                    hazard.Resolved = true;
                    if (Mathf.Abs(hazard.Lane - lane) < 1.5f)
                    {
                        health = Mathf.Max(0, health - .25f);
                        if (health <= 0) EndRun();
                    }
                    else dodgeCount++;
                }
                if (z > 70) hazard.Root.SetActive(false);
            }
        }

        private void EndRun()
        {
            Running = false; finished = true; CancelSteering();
            menu.SetActive(true); controls.SetActive(false); hudPanel.SetActive(false);
            resultText.text = ((int)Distance) + " METERS  /  $" + Cash + " EARNED\n" + dodgeCount + " barriers avoided";
        }

        private void UpdateHUD()
        {
            distanceText.text = ((int)Distance) + " m";
            speedText.text = ((int)SpeedKPH) + " KM/H";
            cashText.text = "$" + Cash;
            healthText.text = "JEEP " + Mathf.CeilToInt(health * 100) + "%";
        }

        private void MakeInterface()
        {
            canvas = new GameObject("Touch interface").AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvas.gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1000, 460); scaler.matchWidthOrHeight = .5f;
            canvas.gameObject.AddComponent<GraphicRaycaster>();
            if (FindAnyObjectByType<EventSystem>() == null)
            {
                var events = new GameObject("Multi-touch events");
                events.AddComponent<EventSystem>(); events.AddComponent<StandaloneInputModule>();
            }
            safeArea = Rect("Safe area", canvas.transform, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            UpdateSafeArea();
            var hud = Rect("HUD", safeArea, Vector2.zero, Vector2.one, new Vector2(22, 18), new Vector2(-22, -18));
            hudPanel = hud.gameObject;
            Label(hud, "THE DRIVE", 24, new Vector2(0, 1), new Vector2(0, 1), new Vector2(0, -10), new Vector2(260, 40));
            Label(hud, "GUJARAT / DESERT ESCAPE", 10, new Vector2(0, 1), new Vector2(0, 1), new Vector2(0, -47), new Vector2(300, 20), Sand);
            distanceText = Label(hud, "0 m", 22, Vector2.one, Vector2.one, new Vector2(-380, -12), new Vector2(125, 34));
            speedText = Label(hud, "72 KM/H", 22, Vector2.one, Vector2.one, new Vector2(-245, -12), new Vector2(155, 34), Sand);
            cashText = Label(hud, "$0", 22, Vector2.one, Vector2.one, new Vector2(-80, -12), new Vector2(80, 34), Sand);
            healthText = Label(hud, "JEEP 100%", 12, Vector2.one, Vector2.one, new Vector2(-130, -50), new Vector2(130, 25));
            controls = Rect("Driving controls", safeArea, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero).gameObject;
            Hold("<", controls.transform, new Vector2(68, 53), pressed => leftHeld = pressed);
            Hold(">", controls.transform, new Vector2(158, 53), pressed => rightHeld = pressed);
            var pause = Button("PAUSE", controls.transform, new Vector2(1, 0), new Vector2(-80, 53), new Vector2(112, 48), () => SetPaused(true));
            pause.name = "Pause";
            menu = Panel("Market menu", safeArea, new Color(0, 0, 0, .38f));
            Label(menu.transform, "MARKET ROAD", 12, new Vector2(0, 1), new Vector2(0, 1), new Vector2(44, -68), new Vector2(360, 25), Sand);
            Label(menu.transform, "THE\nDRIVE", 58, new Vector2(0, .5f), new Vector2(0, .5f), new Vector2(44, 110), new Vector2(400, 150));
            resultText = Label(menu.transform, "A quiet bazaar. An old Jeep.\nA long way out.", 16, new Vector2(0, .5f), new Vector2(0, .5f), new Vector2(44, -40), new Vector2(420, 60));
            var play = Button("HIT THE ROAD", menu.transform, Vector2.zero, new Vector2(150, 70), new Vector2(212, 58), StartRun);
            play.name = "Start";
            Button("NEW ROUTE", menu.transform, new Vector2(1, 0), new Vector2(-110, 70), new Vector2(170, 48), NewRoute);
            seedText = Label(menu.transform, "ROUTE", 10, Vector2.zero, Vector2.zero, new Vector2(44, 25), new Vector2(600, 20), Sand);
            pausePanel = Panel("Paused", safeArea, new Color(0, 0, 0, .7f));
            Label(pausePanel.transform, "ROAD ON HOLD", 32, new Vector2(.5f, .5f), new Vector2(.5f, .5f), new Vector2(-180, 45), new Vector2(360, 60));
            Button("RESUME", pausePanel.transform, new Vector2(.5f, .5f), new Vector2(0, -35), new Vector2(210, 56), () => SetPaused(false));
        }

        private void Hold(string title, Transform parent, Vector2 position, Action<bool> changed)
        {
            var button = Button(title, parent, Vector2.zero, position, new Vector2(74, 66), () => { });
            var hold = button.gameObject.AddComponent<HoldControl>();
            hold.Changed = changed;
            holdControls.Add(hold);
        }
        private Button Button(string title, Transform parent, Vector2 anchor, Vector2 position, Vector2 size, UnityEngine.Events.UnityAction action)
        {
            var rt = Rect(title, parent, anchor, anchor, Vector2.zero, Vector2.zero);
            rt.pivot = new Vector2(.5f, .5f); rt.sizeDelta = size; rt.anchoredPosition = position;
            var image = rt.gameObject.AddComponent<Image>(); image.color = Sand;
            var button = rt.gameObject.AddComponent<Button>(); button.targetGraphic = image; button.onClick.AddListener(action);
            var text = Label(rt, title, title.Length > 1 ? 15 : 32, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, new Color(.09f, .08f, .065f));
            text.rectTransform.offsetMin = Vector2.zero; text.rectTransform.offsetMax = Vector2.zero; text.alignment = TextAnchor.MiddleCenter;
            return button;
        }
        private Text Label(Transform parent, string value, int size, Vector2 min, Vector2 max, Vector2 position, Vector2 dimensions, Color? color = null)
        {
            var rt = Rect(value, parent, min, max, Vector2.zero, Vector2.zero);
            rt.pivot = new Vector2(0, 1); rt.sizeDelta = dimensions; rt.anchoredPosition = position;
            var text = rt.gameObject.AddComponent<Text>(); text.text = value; text.font = font; text.fontSize = size;
            text.fontStyle = FontStyle.Bold; text.color = color ?? Color.white;
            text.horizontalOverflow = HorizontalWrapMode.Wrap; text.verticalOverflow = VerticalWrapMode.Overflow;
            text.raycastTarget = false;
            return text;
        }
        private GameObject Panel(string name, Transform parent, Color color)
        {
            var rt = Rect(name, parent, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            rt.gameObject.AddComponent<Image>().color = color;
            return rt.gameObject;
        }
        private static RectTransform Rect(string name, Transform parent, Vector2 min, Vector2 max, Vector2 lower, Vector2 upper)
        {
            var rt = new GameObject(name, typeof(RectTransform)).GetComponent<RectTransform>();
            rt.SetParent(parent, false); rt.anchorMin = min; rt.anchorMax = max; rt.offsetMin = lower; rt.offsetMax = upper;
            return rt;
        }
        private void UpdateSafeArea()
        {
            if (safeArea == null || safeRect == Screen.safeArea) return;
            safeRect = Screen.safeArea;
            safeArea.anchorMin = new Vector2(safeRect.x / Screen.width, safeRect.y / Screen.height);
            safeArea.anchorMax = new Vector2(safeRect.xMax / Screen.width, safeRect.yMax / Screen.height);
            safeArea.offsetMin = safeArea.offsetMax = Vector2.zero;
        }
        private void CancelSteering()
        {
            foreach (var hold in holdControls) hold.Cancel();
            leftHeld = rightHeld = false;
        }
        private void OnApplicationPause(bool paused) { backgrounded = paused; CancelSteering(); }
        private void OnApplicationFocus(bool focus) { backgrounded = !focus; if (!focus) CancelSteering(); }
        private void OnDestroy()
        {
            if (Instance == this) Instance = null;
            if (hazardMaterial) Destroy(hazardMaterial);
        }
    }
}
