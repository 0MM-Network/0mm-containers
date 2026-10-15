# atlas-lean vLLM workload

`localhost/0mm-atlas-lean-vllm:local` — GPU OpenAI-compat serve for I0/C1:

- Binds `127.0.0.1:18100` (not 8000)
- Model pin `AI-MO/Kimina-Prover-RL-0.6B`
- Weights: `$PROJECT_DIR/cache/models/Kimina-Prover-RL-0.6B/weights/`

Not the CPU Lean image. Not Pi. Start explicitly (`run.sh`); catalog deployment `serve-kimina-06b-vllm` stays disabled so first_mile GPU mutex is opt-in.

```text
0mm-containers/atlas-lean-vllm/build.sh
0mm-containers/atlas-lean-vllm/run.sh
```
