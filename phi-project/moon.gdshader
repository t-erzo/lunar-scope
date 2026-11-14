shader_type spatial;
uniform sampler2D heightmap : filter_linear, repeat_enable;
uniform float height_scale = 0.5;

void vertex() {
    float h = texture(heightmap, UV).r;
    VERTEX += NORMAL * h * height_scale;
}
