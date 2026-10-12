# harmonized_gpu_info

A source-cited, `jq`/`yq`-friendly JSON reference for NVIDIA datacenter GPUs (training and inference accelerators). NVIDIA doesn't expose an API for this data — specs are scattered across datasheets, product briefs, and third-party sites with inconsistent units and no per-field provenance. This project normalizes everything into one flat, comparable schema, with every number traceable back to where it came from.

## Why this exists

Several public GPU-spec datasets already exist (e.g. [gmasse/gpu-specs](https://github.com/gmasse/gpu-specs), [RightNow-GPU-Database](https://github.com/RightNow-AI/RightNow-GPU-Database)), but none of them:
- Model rack-scale systems (GB200 NVL72, GB300 NVL72) and multi-GPU nodes (HGX B200/B300) as first-class records alongside single chips
- Track NVLink/interconnect bandwidth as a first-class field
- Cite sources per-field (most give one source list per record, if any)
- Distinguish the same silicon binned differently across host systems (e.g. B300 in HGX B300 vs. GB300 NVL72 ship at different power/memory limits despite being "the same GPU")

This project is scoped narrowly to NVIDIA datacenter GPUs used for training/inference — no consumer cards, no AMD/Intel.

## Layout

```
harmonized_gpu_info/
  schema/
    gpu.schema.json        JSON Schema for a single GPU chip/SKU
    system.schema.json     JSON Schema for a multi-GPU node or rack
  gpus/                    One file per exact GPU SKU (chip + form factor + memory config)
  systems/                 One file per multi-GPU node (tier: "node") or rack (tier: "rack")
  scripts/
    validate.py            Validates every record against its schema
  .venv/                   Local venv (uv-managed) with jsonschema installed
```

### File naming

`<model>-<form-factor>-<memory-or-variant>.json`, kebab-case — one exact SKU per file, so two files diff cleanly:

```
gpus/h100-sxm-80gb.json
gpus/h100-pcie-80gb.json
gpus/h100-nvl-94gb.json
gpus/b300-sxm-hgx.json           # B300 chip as binned inside HGX B300
gpus/b300-sxm-gb300nvl72.json    # same B300 chip, higher-binned inside GB300 NVL72
```

## Schema design

### GPU form factors (`form_factor` field)

- **PCIe** — standard card, power-capped by the slot, NVLink absent or bridged.
- **SXM** — proprietary module soldered to an HGX/DGX baseboard, no PCIe edge connector, full NVLink domain, higher TDP ceiling. Has a named socket generation (`sxm_generation`): SXM2 (V100), SXM4 (A100), SXM5 (H100/H200), SXM6 (B200/B300 — Blackwell and Blackwell Ultra share this socket generation).
- **NVL** — physically a PCIe card, but sold/bridged as a multi-card group via a dedicated NVLink bridge. The bridging behavior itself varies by generation — see `nvlink_bridge_gpu_count`.

### Same chip, different bins

NVIDIA bins the same physical chip differently depending on which host system it ships in — e.g. B300 silicon is capped at 1100W/270GB in HGX B300 but 1400W/279GB in GB300 NVL72. These get **separate files** in `gpus/` (`b300-sxm-hgx.json`, `b300-sxm-gb300nvl72.json`), each referenced by exactly one `systems/*.json` record via `gpu_model_ref`.

### Dense vs. sparse compute figures

NVIDIA typically publishes Tensor Core throughput as a single "with sparsity" number, with a footnote stating dense = sparse ÷ 2. This project treats that footnote inconsistently *on purpose*, matching what each source actually states:
- If NVIDIA's own table gives an explicit halving rule (e.g. L4's datasheet: *"Specifications 1/2 lower without sparsity"*), the dense value is **derived** and the `notes` field says so.
- If NVIDIA gives no such explicit rule, or if dense and sparse are independently published (e.g. A100, L40S), the dense field is either the sourced value or left `null` — never silently computed.

Every record's `notes` field states which convention applies.

### Precisions kept separate, even when identical

FP8 and FP6 Tensor Core throughput are the same number on Blackwell/Blackwell Ultra (shared tensor core datapath) — NVIDIA sometimes prints them as one combined "FP8/FP6" row. This schema still keeps `fp8_tensor_sparse_tflops` and `fp6_tensor_sparse_tflops` as two separate fields (both populated with the same value when the source combines them), for the same reason FP16 and BF16 stay separate even though they're also usually numerically identical — one field per precision, consistently, so `jq '.fp6_tensor_sparse_tflops'` works uniformly across every record regardless of how any one source happened to print its table.

### Sourcing: `sources[]` vs `_sources{}`

- `sources`: array of URLs — the primary reference(s) for the record as a whole. Required, non-empty.
- `_sources`: object mapping specific field names to a more specific citation (a different document, or the same document with a page/table reference) when that field's provenance differs from the whole-record `sources[]`.

A field with no entry in `_sources` is sourced from the whole-record `sources[]` list.

### When sources disagree

Multiple records in this dataset have discrepancies between official NVIDIA documents (e.g. an archived "preliminary" datasheet vs. the current live product page; a PCF/sustainability document with an apparent unit typo). The rule followed throughout: **never silently pick one number** — resolve with corroborating evidence when possible (e.g. cross-multiplying a per-GPU figure against a system total), and if unresolved, say so explicitly in `notes` rather than guessing. Search `notes` for "UNRESOLVED" or "discrepancy" to find every flagged case (e.g. `gpus/h100-nvl-94gb.json`). A related but distinct case is `gpus/a10g.json`, where the "discrepancy" turned out to be two genuinely different products (A10 vs. A10G) rather than conflicting sources for one product — see the A10 vs. A10G note above.

### `null` means something specific

A `null` value always means one of:
1. The precision/feature doesn't exist on that architecture (e.g. `fp8_tensor_tflops` is `null` on every Ampere-or-earlier GPU because FP8 Tensor Core didn't exist yet) — not merely "not published."
2. NVIDIA has never published that figure for that exact SKU, and no reliable derivation exists (e.g. H200's core counts — NVIDIA has never stated them for H200 specifically, only for the underlying H100 die it shares).

Both cases are always explained in `notes`.

## Setup

```bash
cd harmonized_gpu_info
uv venv .venv
uv pip install --python .venv jsonschema
```

## Usage

### Validate everything

```bash
.venv/bin/python3 scripts/validate.py
```

Checks every `gpus/*.json` and `systems/*.json` against its schema, and confirms every `systems/*.json`'s `gpu_model_ref` resolves to a real file in `gpus/`.

### Compare GPUs with `jq`

```bash
# Sort every GPU by memory bandwidth
jq -s 'map({name, memory_capacity_gb, memory_bandwidth_gbps, tdp_watts_max}) | sort_by(.memory_bandwidth_gbps)' gpus/*.json

# Find every GPU with FP8 support
jq -s 'map(select(.fp8_tensor_sparse_tflops != null) | {name, fp8_tensor_sparse_tflops})' gpus/*.json
```

### Diff two SKUs directly

```bash
diff <(jq -S . gpus/h100-sxm-80gb.json) <(jq -S . gpus/h200-sxm-141gb.json)
# or, interactively:
vimdiff gpus/h100-sxm-80gb.json gpus/h200-sxm-141gb.json
```

Because every record is flat (no nested `{value, source}` wrappers), every field diffs on its own line.

## Coverage

**GPUs:** A10, A10G, L4, L40S, V100 SXM2, A100 (SXM4 40GB, SXM4 80GB, PCIe 80GB), H100 (SXM, PCIe, NVL), H200 (SXM, NVL), B200 (HGX-binned, GB200 NVL72-binned), B300 (HGX-binned, GB300 NVL72-binned).

**Note on A10 vs. A10G:** these are two genuinely different NVIDIA Ampere parts, not one part under two names — confirmed via an AWS-published NVIDIA datasheet distinct from NVIDIA's own A10 datasheet. A10G has a higher TDP (300W vs 150W) and more RT cores (80 vs 72), but *lower* Tensor Core throughput at every precision except plain FP32 — see `gpus/a10g.json`'s `notes` for the full comparison and a flagged anomaly in the source data.

**Systems:** HGX B200, HGX B300, GB200 NVL72, GB300 NVL72.

Not yet covered: GB200/GB300 NVL72 rack-level power draw (not stated in the primary NVIDIA datasheet used; flagged as a follow-up in the relevant `notes`), and joining this data against AWS EC2 `DescribeInstanceTypes` GPU names (e.g. matching `GpuInfo.Gpus[].Name` to a canonical record here) — a planned follow-up, not part of this dataset.
