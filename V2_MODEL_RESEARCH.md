# Piano transcribe V2 model research

Sources checked: 2026-10-02. No models were installed, downloaded, or executed. This document separates upstream evidence from proposed experiments.

Read the [V2 review](/Users/filip/Developer/piano-transcribe/V2_REVIEW.md) for current implementation defects and the [V2 plan](/Users/filip/Developer/piano-transcribe/V2_PLAN.md) for adoption criteria.

## Transcription candidates

### Transkun V2 remains the baseline

The latest PyPI release remains 2.0.1, released September 28, 2024. The wheel is about 50.8 MB, not the size of a complete Python and Torch bundle. [Transkun on PyPI](https://pypi.org/project/transkun/).

The upstream model cards distinguish packaged V2 No Pedal Ext, benchmark V2, and V2 Aug. No Pedal Ext does not extend note labels through sustain-pedal durations. Different offset conventions make their published offset scores unsuitable for direct ranking. V2 Aug is the lowest-cost additional experiment because it uses the existing engine. The repository and package declare MIT; separately downloaded checkpoint provenance still needs recording. [Official Transkun model cards](https://github.com/Yujia-Yan/Transkun#model-cards).

Keep the packaged checkpoint as the default during V2 development. Neither the word benchmark nor a newer release establishes better results on Filip's recordings.

### MuScriptor is the most relevant new Mac-ready experiment

Kyutai and Mirelo announced MuScriptor on July 10, 2026. It targets multi-instrument audio-to-MIDI rather than only clean piano. Its reported general-music improvements are not a controlled comparison against Transkun on piano concertos. [Official announcement](https://kyutai.org/blog/2026-07-10-muscriptor/).

Upstream supports Apple Silicon MPS and recommends small for CPU. Its variants have approximately 103M, 307M, and 1.4B parameters. Local safetensors paths support offline loading after build-time asset acquisition. Start evaluation with small and medium, not large. Model-file and final bundle sizes were not verified. [Official MuScriptor repository](https://github.com/muscriptor/muscriptor).

The representation uses five-second chunks and emits pitch, note timing, and instrument events, but not velocity or dynamics. Instrument conditioning and piano-track selection deserve testing on full mixes. Those paths do not generate isolated audio stems. The code is MIT; weights are CC BY-NC 4.0, gated behind license acceptance with supplemental conditions. Bundling assets removes first-run downloads, not those conditions. [MuScriptor model card and terms](https://huggingface.co/MuScriptor/muscriptor-small).

Recommendation: evaluate a separate note-only full-mix workflow. Do not silently replace expressive piano output with fixed-velocity MIDI.

### Aria-AMT is piano-specific but requires a Mac port

Aria-AMT's tokenizer represents note events, velocity, and sustain pedal. The official checkpoint is about 447 MB, with 16 kHz input and 30-second windows. Those are representation and deployment facts, not proof of superior accuracy. [Official Aria-AMT repository](https://github.com/EleutherAI/aria-amt), [tokenizer](https://github.com/EleutherAI/aria-amt/blob/main/amt/tokenizer.py), [checkpoint listing](https://huggingface.co/datasets/loubb/aria-midi/tree/main).

Upstream asserts CUDA availability and uses CUDA-specific placement and autocast. CPU or MPS support requires an adapter or a maintained port, followed by output-parity tests. Changing a device string is insufficient. [CUDA requirement](https://github.com/EleutherAI/aria-amt/blob/main/amt/run.py#L371), [inference implementation](https://github.com/EleutherAI/aria-amt/blob/main/amt/inference/transcribe.py#L125).

Code is Apache-2.0. The checkpoint is hosted in a dataset repository labelled CC-BY-NC-SA-4.0; this research did not locate a separately scoped checkpoint license. Treat the weight terms as unresolved rather than assuming the code license covers them. [Aria-MIDI dataset card](https://huggingface.co/datasets/loubb/aria-midi).

Recommendation: evaluate after the existing-engine checkpoint comparison and MuScriptor feasibility test. A promising model is not yet a shippable Mac backend.

### Smaller native runtimes are possible, but not an automatic quality upgrade

Basic Pitch offers official CoreML and ONNX runtime choices. It is an instrument-agnostic option for a smaller engine, not established here as a better expressive-piano model. [Basic Pitch runtime documentation](https://github.com/spotify/basic-pitch#model-runtime).

The older ByteDance piano model is a useful pedal-aware baseline, not a new-model upgrade. CUDA-focused research implementations and audio-to-score systems do not solve this app's offline Mac audio-to-MIDI contract without additional work. Package no extra model merely to increase the model count.

## Separation candidates

### HDMC remains the concerto baseline

The current app pins `pc-separation` to `9edb8126a2ebb93852917da06d2ce3619ea15c4d` and bundles HDMC. Upstream specifically targets piano and orchestral tracks in concerto recordings. Its older environment justifies isolation while replacements are evaluated. Source metadata declares MIT, but a root license file and separately clear checkpoint redistribution terms were not located. Preserve the user's previously chosen best-effort public-bundling policy without pretending uncertainty has disappeared. [pc-separation repository](https://github.com/yiitozer/pc-separation), [environment](https://raw.githubusercontent.com/yiitozer/pc-separation/refs/heads/master/environment.yml), [source metadata](https://raw.githubusercontent.com/yiitozer/pc-separation/master/setup.py).

No verified newer, downloadable, score-free concerto model was found with demonstrated superiority over HDMC under the same evaluation protocol.

### BS-RoFormer SW is the main quality challenger

SW produces six explicit stems, including piano. It is not a generic vocals-versus-instrumental model. The current mirrored checkpoint is about 699 MB. Its model card states that the weight license is unknown after the original host disappeared. An MIT architecture does not resolve the checkpoint terms. [SW checkpoint model card](https://huggingface.co/enerjazzer/BS-ROFO-SW-Fixed).

Mac integration options include a maintained separator framework documenting RoFormer MPS support and an inference-only implementation with explicit offline paths. The latter does not currently support MPS or MLX. Test runtime behavior rather than assuming either framework is optimal. [python-audio-separator](https://github.com/nomadkaraoke/python-audio-separator), [bs-roformer-infer](https://github.com/openmirlab/bs-roformer-infer).

Recommendation: compare SW followed by the same Transkun checkpoint against HDMC followed by that checkpoint. Do not rank concerto quality from unrelated piano leaderboards.

### SW ONNX could remove the second Torch runtime

A community export provides roughly 336 MB fp16-stored and 669 MB fp32 models. It uses fixed four-second chunks. FP16 storage does not imply FP16 compute or proportionately lower working memory. The exporter describes graph rewrites and acknowledges unclear upstream weight provenance. [SW ONNX model card](https://huggingface.co/elicwhite/bs-roformer-sw-6stem-onnx), [export and validation repository](https://github.com/elicwhite/bs-roformer-web).

Recommendation: test output parity, chunk boundaries, and Mac memory before choosing a native ONNX Runtime adapter. CoreML acceleration and unchanged concerto quality are not yet established for this export.

### A compact piano model is a useful footprint experiment

`tjpurdy/Piano-Separation-Model-small` is an approximately 17 MB, 8.8M-parameter acoustic-piano separator. Weights are CC-BY-NC-4.0. Its supplied implementation selects CPU or CUDA and retains whole-track buffers despite chunked inference. No concerto comparison was located. [Model card](https://huggingface.co/tjpurdy/Piano-Separation-Model-small), [inference implementation](https://raw.githubusercontent.com/tjpurdy/Piano-Separation-Model-small/main/inference.py).

Recommendation: optional small-runtime challenger. For a piano-only model, mixture minus piano is a residual, not an independently estimated orchestra stem.

### Other models do not yet justify replacing HDMC

An HT-Demucs six-stem ONNX export offers about 136 MB fp16-stored and 258 MB fp32 assets. It is useful as a runtime baseline, but original Demucs documentation warns about piano bleed and artifacts. Publisher M4 Pro timing is not a measurement on our machine. [ONNX export](https://huggingface.co/StemSplitio/htdemucs-6s-onnx), [original Demucs](https://github.com/facebookresearch/demucs).

SAM Audio supports prompted target and residual separation, but its large model stack has no established long-concerto Mac performance in the material examined. Keep it research-only. [Official SAM Audio model card](https://huggingface.co/facebook/sam-audio-small).

SCISSOR's September 2026 research addresses score-conditioned orchestral separation. Requiring an aligned score changes this app's audio-only workflow, and usable drop-in weights were not verified. [SCISSOR paper](https://arxiv.org/abs/2609.33265).

## Controlled comparison

Freeze a small corpus of legally usable solo piano, piano concerto, and no-piano excerpts. Include quiet notes, fast repetition, pedalling, reverberation, dense tutti, and long recordings. Do not commit copyrighted user tracks or datasets without redistribution rights.

Relevant concerto resources include separate reference stems and a notewise evaluation extension with aligned scores. Confirm their use terms and annotation suitability before selecting fixtures. [PCD dataset](https://audiolabs-erlangen.de/resources/MIR/PCD), [ISMIR 2024 piano-separation evaluation](https://www.audiolabs-erlangen.de/resources/MIR/2024-ISMIR-PianoSepEval).

Evaluate these comparisons independently:

1. Packaged Transkun versus benchmark V2 versus V2 Aug on identical clean piano audio.
2. HDMC versus SW with one fixed Transkun checkpoint.
3. SW PyTorch versus SW ONNX for numerical and musical parity.
4. Direct MuScriptor full-mix piano output versus the complete separation-to-Transkun pipeline.
5. Aria-AMT only after a working Mac port passes parity tests.

Record onset and offset metrics under identical tolerances and pedal conventions. Report velocity and pedal separately. Report missing capabilities instead of assigning a note-only model an expressive-piano score.

Measure cold start, real-time factor, peak process and accelerator memory, cancellation, output timing, and chunk artifacts on representative 8 GB and 16 GB Apple Silicon Macs. Listen to blind stem and MIDI comparisons. A separator's SDR alone does not establish better MIDI.

Adopt a new default only after measured improvement on the target corpus and acceptable offline Mac reliability. Keep the packaged Transkun default until that decision is explicit. Bundle only selected models, not the entire research shortlist.
