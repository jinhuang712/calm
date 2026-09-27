// Calm Terminal — cursor glide.
//
// Right after the cursor jumps (not when typing moves it one cell), draw a short, soft
// smear from where it was to where it is, fading out in about 140 ms. The terminal's own
// cursor is still drawn at the new position; this only suggests the motion.
//
// Ghostty custom-shader uniforms: iCurrentCursor / iPreviousCursor are (x, y, width, height)
// in pixels with a bottom-left origin, where y is the cursor's top edge.

const float DURATION = 0.14;   // seconds
const float MAX_ALPHA = 0.32;  // soft, never a flash
const float MIN_CELLS = 2.5;   // ignore moves shorter than this many cell widths

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);

    float t = (iTime - iTimeCursorChange) / DURATION;
    if (t >= 1.0 || t < 0.0 || iCursorVisible == 0) {
        return;
    }

    vec4 current = iCurrentCursor;
    vec4 previous = iPreviousCursor;
    vec2 from = vec2(previous.x + previous.z * 0.5, previous.y - previous.w * 0.5);
    vec2 to = vec2(current.x + current.z * 0.5, current.y - current.w * 0.5);

    float travel = distance(from, to);
    if (travel < max(current.z, 1.0) * MIN_CELLS) {
        return;
    }

    // Ease out: the head arrives quickly, the tail follows and catches up.
    float head = 1.0 - pow(1.0 - t, 3.0);
    float tail = clamp((head - 0.35) / 0.65, 0.0, 1.0);
    vec2 a = mix(from, to, tail);
    vec2 b = mix(from, to, head);

    // Distance to the capsule from a to b, as thick as the cursor.
    vec2 pa = fragCoord - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    float radius = min(current.z, current.w) * 0.5;
    float d = length(pa - ba * h) - radius;

    float alpha = (1.0 - smoothstep(0.0, 1.5, d)) * (1.0 - t) * MAX_ALPHA;
    fragColor = mix(fragColor, vec4(iCurrentCursorColor.rgb, 1.0), alpha);
}
