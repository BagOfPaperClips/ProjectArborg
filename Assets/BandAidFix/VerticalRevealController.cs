using UnityEngine;

/// <summary>
/// Attach this to any GameObject using the VerticalReveal shader.
/// Call Reveal() / Hide() from code, or let it auto-play on Start.
/// </summary>
[RequireComponent(typeof(Renderer))]
public class VerticalRevealController : MonoBehaviour
{
    [Header("Timing")]
    [Tooltip("How many seconds the full reveal takes.")]
    public float revealDuration = 2f;

    [Tooltip("Delay before the reveal starts (seconds).")]
    public float startDelay = 0f;

    [Tooltip("Play the reveal automatically when the scene starts.")]
    public bool autoReveal = true;

    [Header("Curve")]
    [Tooltip("Controls the easing of the reveal. Default is linear.")]
    public AnimationCurve easeCurve = AnimationCurve.EaseInOut(0f, 0f, 1f, 1f);

    // ----------------------------------------------------------------
    // Private state
    // ----------------------------------------------------------------
    private Material _mat;
    private float    _elapsed   = 0f;
    private float    _delayLeft = 0f;
    private bool     _running   = false;
    private bool     _revealing = true;   // true = reveal, false = hide

    // Cached shader property ID for performance
    private static readonly int ProgressID = Shader.PropertyToID("_Progress");

    // ----------------------------------------------------------------
    // Unity callbacks
    // ----------------------------------------------------------------
    void Awake()
    {
        // Use a per-instance material copy so multiple objects are independent
        _mat = GetComponent<Renderer>().material;
        _mat.SetFloat(ProgressID, 0f);
    }

    void Start()
    {
        if (autoReveal)
            Reveal();
    }

    void Update()
    {
        if (!_running) return;

        // Wait out the start delay
        if (_delayLeft > 0f)
        {
            _delayLeft -= Time.deltaTime;
            return;
        }

        _elapsed += Time.deltaTime;
        float t = Mathf.Clamp01(_elapsed / revealDuration);
        float progress = easeCurve.Evaluate(_revealing ? t : 1f - t);

        _mat.SetFloat(ProgressID, progress);

        if (t >= 1f)
            _running = false;
    }

    // ----------------------------------------------------------------
    // Public API
    // ----------------------------------------------------------------

    /// <summary>Start (or restart) the reveal from bottom to top.</summary>
    public void Reveal()
    {
        _revealing  = true;
        _elapsed    = 0f;
        _delayLeft  = startDelay;
        _running    = true;
    }

    /// <summary>Animate back to fully hidden (top to bottom disappear).</summary>
    public void Hide()
    {
        _revealing  = false;
        _elapsed    = 0f;
        _delayLeft  = 0f;
        _running    = true;
    }

    /// <summary>Jump to a specific reveal amount without animation (0 = hidden, 1 = fully shown).</summary>
    public void SetProgress(float value)
    {
        _running = false;
        _mat.SetFloat(ProgressID, Mathf.Clamp01(value));
    }
}
