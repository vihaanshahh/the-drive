using System;
using UnityEngine;
using UnityEngine.EventSystems;

namespace TheDrive.UnityGame
{
    /// <summary>Independent pointer ownership keeps simultaneous multi-touch steering predictable.</summary>
    public sealed class HoldControl : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        public Action<bool> Changed;
        private int pointer = int.MinValue;
        public bool IsHeld => pointer != int.MinValue;
        public void OnPointerDown(PointerEventData data)
        {
            if (pointer != int.MinValue) return;
            pointer = data.pointerId;
            Changed?.Invoke(true);
        }
        public void OnPointerUp(PointerEventData data)
        {
            if (data.pointerId != pointer) return;
            Cancel();
        }
        public void OnPointerExit(PointerEventData data) { OnPointerUp(data); }
        private void OnDisable() { Cancel(); }
        public void Cancel()
        {
            if (pointer == int.MinValue) return;
            pointer = int.MinValue;
            Changed?.Invoke(false);
        }
    }
}
