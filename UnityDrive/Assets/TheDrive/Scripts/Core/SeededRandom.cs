using System;

namespace TheDrive.UnityGame
{
    /// <summary>Small deterministic SplitMix64 generator, matching the route's seeded hash family.</summary>
    public struct SeededRandom
    {
        public ulong State { get; private set; }

        public SeededRandom(ulong seed) { State = seed; }

        public ulong NextULong()
        {
            unchecked
            {
                State += 0x9E3779B97F4A7C15UL;
                ulong z = State;
                z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                return z ^ (z >> 31);
            }
        }

        public float Range(float minimum, float maximum)
        {
            double unit = (NextULong() >> 11) / 9007199254740992.0;
            return (float)(minimum + (maximum - minimum) * unit);
        }

        public int Range(int minimum, int maximumExclusive)
        {
            if (maximumExclusive <= minimum) throw new ArgumentOutOfRangeException(nameof(maximumExclusive));
            ulong width = (ulong)((long)maximumExclusive - minimum);
            return (int)(minimum + (long)(NextULong() % width));
        }
    }
}
