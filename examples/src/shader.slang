[[vk::binding(0)]]
RWStructuredBuffer<uint32_t> buf_one;

[[vk::binding(1)]]
RWStructuredBuffer<float32_t> buf_two;

[[vk::binding(2)]]
RWStructuredBuffer<float64_t> buf_three;

[[vk::binding(3)]]
RWTexture2D<float4> buf_four;

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 threadID : SV_DispatchThreadID) {
    uint id = threadID.x;

    buf_one[id] = buf_one[id] + buf_one[id];
    buf_two[id] = buf_two[id] * buf_two[id];
    buf_three[id] = 1.0 / buf_three[id];
    buf_four[uint2(0, 0)] = float4(0.0, 0.5, 1.0, 0.5);
}
