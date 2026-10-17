# Qwen V3 continuation training runbook

Status: preparation only; training not started.

## Model safety
Keep qwen-chatgpt-v2:9b and all V2 files frozen. Continue fine-tuning from the V2 merged 9B checkpoint using a new LoRA adapter. Write V3 outputs only to a separate directory. Deploy as qwen-mygitea2-v3:9b in Q4_K_M after evaluation.

## Verified preparation
MyGitea2 inventory: 151 repositories, 143 with valid branches and 8 without. Manifest: 395346 entries; filename screening retained 304727 candidates. First local content pilot: 120 unique files, zero hash mismatches, all from mygitea2.git; quarantined. Balanced planning: maximum 250 candidates per project, 25929 candidates across 143 projects. V2 merged checkpoint and adapter confirmed present; V3 output absent at preflight.

## Required next stages
1. Extract balanced samples from all eligible projects, preserving repository, commit and path provenance.
2. Exclude binaries, duplicates, credentials, generated artifacts and unlicensed or unsuitable material. Do not publish unscreened content.
3. Build training examples and a project-separated validation set.
4. Test loading the frozen V2 merged checkpoint for a new LoRA training run; verify GPU memory and record configuration, versions, seed and hashes.
5. Train and save only new V3 artifacts; compare with V2 for regressions.
6. Merge, quantize and register the new V3 model separately, keeping V2 operational.

## Reproducibility
Record dataset manifest and SHA256, Git refs, filtering rules, splits, scripts, hyperparameters, checkpoints, metrics, evaluation and deployment commands. A planned stage is not a PASS until independently verified. Do not modify the Gitea server or frozen TheHands runtime.
