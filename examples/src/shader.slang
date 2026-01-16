RWStructuredBuffer<uint32_t> buf_one;
RWStructuredBuffer<float32_t> buf_two;
RWStructuredBuffer<float64_t> buf_three;
RWStructuredBuffer<int32_t> buf_four;

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 threadID : SV_DispatchThreadID) {
    uint id = threadID.x;

    buf_one[id] = buf_one[id] + buf_one[id];
    buf_two[id] = buf_two[id] * buf_two[id];
    buf_three[id] = 1.0 / buf_three[id];
    buf_four[id] = int(id) - 4;
}
