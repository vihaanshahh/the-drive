using System;

namespace TheDrive.UnityGame
{
    public struct RoadSample
    {
        public float Height;
        public float Pitch;
        public float Roll;
        public float Roughness;

        public RoadSample(float height, float pitch, float roll, float roughness)
        { Height = height; Pitch = pitch; Roll = roll; Roughness = roughness; }

        public static RoadSample Flat => new RoadSample(0, 0, 0, 0);
    }

    /// <summary>Continuous road surface; distance increases along world -Z and x points right.</summary>
    public static class RoadSurface
    {
        public const float Wheelbase = 2.4f;
        public const float TrackWidth = 1.8f;

        public static float Height(double distance, float x, ulong seed)
        {
            if (!Finite(distance) || !Finite(x)) return 0;
            double lateral = Math.Min(5.7, Math.Max(-5.7, x));
            double hills = BroadHeight(distance, seed);
            double bank = (0.018 * Wave(distance, 89, seed, 11) + 0.009 * Noise(distance / 57, seed, 12)) * lateral;
            double bumps = 0.065 * Noise(distance / 8 + lateral * 0.22, seed, 21)
                         + 0.028 * Noise(distance / 3 - lateral * 0.37, seed, 22);
            return (float)(hills + bank + bumps + Potholes(distance, lateral, seed));
        }

        public static RoadSample Sample(double distance, float x, ulong seed)
        {
            if (!Finite(distance) || !Finite(x)) return RoadSample.Flat;
            double halfLength = Wheelbase / 2.0, halfWidth = TrackWidth / 2.0;
            float fl = Height(distance + halfLength, (float)(x - halfWidth), seed);
            float fr = Height(distance + halfLength, (float)(x + halfWidth), seed);
            float rl = Height(distance - halfLength, (float)(x - halfWidth), seed);
            float rr = Height(distance - halfLength, (float)(x + halfWidth), seed);
            float front = (fl + fr) / 2, rear = (rl + rr) / 2;
            float left = (fl + rl) / 2, right = (fr + rr) / 2;
            float mean = (front + rear) / 2;
            float unevenness = Math.Abs(fl + rr - fr - rl) / 4;
            float shortBump = Math.Abs(mean - (float)BroadHeight(distance, seed));
            return new RoadSample(mean, (float)Math.Atan2(front - rear, Wheelbase),
                (float)Math.Atan2(right - left, TrackWidth), Math.Min(1, unevenness * 7 + shortBump * 3));
        }

        private static double BroadHeight(double d, ulong seed) => 0.34 * Wave(d, 113, seed, 1) + 0.19 * Wave(d, 83, seed, 2) + 0.08 * Noise(d / 132, seed, 3);
        private static double Wave(double d, double wavelength, ulong seed, ulong salt)
        {
            double phase = UnitHash(0, seed, salt) * 2 * Math.PI;
            return Math.Sin((d / wavelength % 1) * 2 * Math.PI + phase);
        }
        private static double Noise(double coordinate, ulong seed, ulong salt)
        {
            double bounded = Math.Abs(coordinate) < 9e18 ? coordinate : coordinate % 1073741824.0;
            double baseValue = Math.Floor(bounded), fraction = bounded - baseValue;
            double blend = fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10);
            long index = (long)baseValue;
            double first = UnitHash(index, seed, salt), second = UnitHash(unchecked(index + 1), seed, salt);
            return (first + (second - first) * blend) * 2 - 1;
        }
        private static double Potholes(double distance, double x, ulong seed)
        {
            double raw = distance / 17;
            double coordinate = Math.Abs(raw) < 9e18 ? raw : raw % 1073741824.0;
            long cell = (long)Math.Floor(coordinate);
            double local = (coordinate - cell) * 17, depression = 0;
            for (int offset = -1; offset <= 1; offset++)
            {
                long index = unchecked(cell + offset);
                if (UnitHash(index, seed, 31) <= 0.38) continue;
                double centerZ = UnitHash(index, seed, 32) * 17 + offset * 17;
                double centerX = (UnitHash(index, seed, 33) * 2 - 1) * 4.3;
                double length = 0.8 + UnitHash(index, seed, 34) * 0.8;
                double width = 0.65 + UnitHash(index, seed, 35) * 0.55;
                double dz = (local - centerZ) / length, dx = (x - centerX) / width;
                double radiusSquared = dx * dx + dz * dz;
                if (radiusSquared >= 1) continue;
                double envelope = 1 - radiusSquared;
                depression -= (0.07 + UnitHash(index, seed, 36) * 0.09) * envelope * envelope * envelope;
            }
            return Math.Max(-0.16, depression);
        }
        internal static double UnitHash(long index, ulong seed, ulong salt)
        {
            unchecked
            {
                ulong value = seed ^ ((ulong)index * 0x9E3779B97F4A7C15UL) ^ (salt * 0xD1B54A32D192ED03UL);
                value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9UL;
                value = (value ^ (value >> 27)) * 0x94D049BB133111EBUL;
                value ^= value >> 31;
                return (value >> 11) / 9007199254740992.0;
            }
        }
        private static bool Finite(double v) => !double.IsNaN(v) && !double.IsInfinity(v);
        private static bool Finite(float v) => !float.IsNaN(v) && !float.IsInfinity(v);
    }

    /// <summary>Exponential visual-body filter; road contacts remain available from RoadSurface.Sample.</summary>
    public sealed class RoadSuspension
    {
        public RoadSample State { get; private set; } = RoadSample.Flat;
        private bool initialized;
        public void Reset(RoadSample sample) { State = sample; initialized = true; }
        public RoadSample Update(RoadSample sample, float dt)
        {
            if (!initialized) { Reset(sample); return State; }
            if (float.IsNaN(dt) || float.IsInfinity(dt) || dt <= 0) return State;
            float step = Math.Min(dt, 0.1f);
            float hb = 1 - (float)Math.Exp(-step * 22), ab = 1 - (float)Math.Exp(-step * 12), rb = 1 - (float)Math.Exp(-step * 9);
            State = new RoadSample(State.Height + (sample.Height - State.Height) * hb,
                State.Pitch + (sample.Pitch - State.Pitch) * ab, State.Roll + (sample.Roll - State.Roll) * ab,
                State.Roughness + (sample.Roughness - State.Roughness) * rb);
            return State;
        }
    }
}
