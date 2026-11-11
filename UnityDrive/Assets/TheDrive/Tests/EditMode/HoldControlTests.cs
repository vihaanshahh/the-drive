using System.Collections.Generic;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;

namespace TheDrive.UnityGame.Tests
{
    public sealed class HoldControlTests
    {
        [Test]
        public void LostTouchCanBeCancelledAndAnotherFingerCanSteer()
        {
            var go = new GameObject("Touch test");
            try
            {
                var hold = go.AddComponent<HoldControl>();
                var calls = new List<bool>();
                hold.Changed = calls.Add;
                var original = new PointerEventData(null) { pointerId = 4 };
                hold.OnPointerDown(original);
                Assert.IsTrue(hold.IsHeld);
                // A pause or app background can swallow the original pointer-up.
                hold.Cancel();
                Assert.IsFalse(hold.IsHeld);
                var next = new PointerEventData(null) { pointerId = 9 };
                hold.OnPointerDown(next);
                Assert.IsTrue(hold.IsHeld);
                hold.OnPointerUp(original);
                Assert.IsTrue(hold.IsHeld, "An old finger's late release must not stop the current finger.");
                hold.OnPointerUp(next);
                Assert.IsFalse(hold.IsHeld);
                CollectionAssert.AreEqual(new[] { true, false, true, false }, calls);
            }
            finally { Object.DestroyImmediate(go); }
        }
    }
}
