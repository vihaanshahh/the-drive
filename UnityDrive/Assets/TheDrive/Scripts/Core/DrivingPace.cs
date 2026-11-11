using System;

namespace TheDrive.UnityGame
{
    public struct PaceSample
    {
        public double BaselineKPH;
        public double TargetKPH;
        public double SlowdownFraction;
        public PaceSample(double baseline, double target, double slowdown) { BaselineKPH = baseline; TargetKPH = target; SlowdownFraction = slowdown; }
    }

    public static class DrivingPace
    {
        public static double Baseline(double distance)
        {
            double d = Finite(distance) ? Math.Max(0, distance) : 0;
            if (d <= 120) return 72 + d * 0.006;
            if (d < 1000) return Interpolate(72.72, 105, (d - 120) / 880);
            if (d < 3000) return Interpolate(105, 125, (d - 1000) / 2000);
            if (d < 6000) return Interpolate(125, 145, (d - 3000) / 3000);
            return 145;
        }
        public static PaceSample Sample(double distance, ulong seed, int engineTier = 0)
        {
            double d = Finite(distance) ? Math.Max(0, distance) : 0;
            double baseline = Baseline(d), block = Math.Floor(d / 1200.0);
            double center = 700 + Unit(seed, block, 1) * 250;
            double seconds = 3.6 + Unit(seed, block, 2) * 0.8;
            double centerPace = Baseline(block * 1200 + center);
            double span = Math.Max(110, centerPace / 3.6 * seconds);
            double phase = d % 1200.0, progress = (phase - center + span / 2) / span, slowdown = 0;
            if (progress > 0 && progress < 1) { double pulse = Math.Sin(progress * Math.PI); slowdown = (0.15 + Unit(seed, block, 3) * 0.10) * pulse * pulse; }
            double bonus = Math.Min(3, Math.Max(0, engineTier)) * 4;
            return new PaceSample(baseline, baseline * (1 - slowdown) + bonus, slowdown);
        }
        public static double FilteredVelocity(double current, double target, double dt)
        {
            if (!Finite(dt) || dt <= 0 || !Finite(target) || target < 0) return current;
            if (!Finite(current)) return target;
            double response = (target - current) * (1 - Math.Exp(-dt / 0.45));
            double change = Math.Min(2.4 * dt, Math.Max(-4.5 * dt, response));
            return Math.Max(0, current + change);
        }
        public static double HazardLead(double velocity)
        { double v = Finite(velocity) ? Math.Max(0, velocity) : 20; return Math.Min(190, Math.Max(130, v * 4.8)); }
        private static double Interpolate(double a, double b, double p) { p = Math.Min(1, Math.Max(0, p)); return a + (b - a) * p * p * (3 - 2 * p); }
        private static double Unit(ulong seed, double block, ulong salt)
        {
            unchecked
            {
                ulong blockBits = unchecked((ulong)BitConverter.DoubleToInt64Bits(block));
                ulong value = seed ^ (blockBits * 0x9E3779B97F4A7C15UL) ^ (salt * 0xD1B54A32D192ED03UL);
                value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9UL;
                value = (value ^ (value >> 27)) * 0x94D049BB133111EBUL;
                value ^= value >> 31;
                return (value >> 11) / 9007199254740992.0;
            }
        }
        private static bool Finite(double d) => !double.IsNaN(d) && !double.IsInfinity(d);
    }
}
