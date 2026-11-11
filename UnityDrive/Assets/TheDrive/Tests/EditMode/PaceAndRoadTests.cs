using NUnit.Framework;

namespace TheDrive.UnityGame.Tests
{
    public class PaceAndRoadTests
    {
        [Test]
        public void RoadIsDeterministicAndSeeded()
        {
            Assert.AreEqual(RoadSurface.Height(812.25, 1.2f, 42), RoadSurface.Height(812.25, 1.2f, 42));
            Assert.AreNotEqual(RoadSurface.Height(812.25, 1.2f, 42), RoadSurface.Height(812.25, 1.2f, 43));
        }

        [Test]
        public void RoadSamplesJoinAcrossChunksAndStayFiniteFarAway()
        {
            const double split = 1000.0;
            float left = RoadSurface.Height(split - 0.001, 0, 123);
            float right = RoadSurface.Height(split + 0.001, 0, 123);
            Assert.That(System.Math.Abs(right - left), Is.LessThan(0.01));
            float far = RoadSurface.Height(1e30, 0, 123);
            Assert.IsFalse(float.IsNaN(far) || float.IsInfinity(far));
            RoadSample sample = RoadSurface.Sample(1e30, 0, 123);
            Assert.IsFalse(float.IsNaN(sample.Pitch) || float.IsInfinity(sample.Pitch));
        }

        [Test]
        public void PaceIsBoundedMostlyFastAndRepeatable()
        {
            int fast = 0;
            for (int i = 0; i < 12000; i++)
            {
                PaceSample p = DrivingPace.Sample(i, 9876);
                Assert.That(p.SlowdownFraction, Is.InRange(0.0, 0.2500001));
                Assert.That(p.TargetKPH, Is.InRange(p.BaselineKPH * 0.749999, p.BaselineKPH));
                if (p.SlowdownFraction < 0.01) fast++;
            }
            Assert.Greater(fast, 9000);
            Assert.AreEqual(DrivingPace.Sample(900, 123).TargetKPH, DrivingPace.Sample(900, 123).TargetKPH);
        }

        [Test]
        public void FilteredVelocityIsFrameRateStable()
        {
            double once = DrivingPace.FilteredVelocity(10, 30, 0.1);
            double split = 10;
            for (int i = 0; i < 10; i++) split = DrivingPace.FilteredVelocity(split, 30, 0.01);
            Assert.That(System.Math.Abs(once - split), Is.LessThan(0.25));
        }
    }
}
