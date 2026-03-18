# Identity Fraud Skills

Cursor AI Skills for the Identity Fraud squad.

## Skills

| Skill | Description |
|---|---|
| `optimize-threshold` | Optimize anti-fraud policy thresholds using Wind Tunnel 4Policies |
| `create-pptx` | Generate PowerPoint presentations with Nubank visual identity |

## Setup

### 1. Clone this repository

```bash
git clone https://github.com/marinaborges2/identity-fraud-skills.git
```

### 2. Symlink skills to Cursor

```bash
mkdir -p ~/.cursor/skills
ln -s $(pwd)/optimize-threshold ~/.cursor/skills/optimize-threshold
ln -s $(pwd)/create-pptx ~/.cursor/skills/create-pptx
```

### 3. Setup assets for `create-pptx`

The `create-pptx` skill requires logo assets extracted from a Nubank reference presentation.

Run the setup script with any Nubank `.pptx` file as reference:

```bash
pip install python-pptx --index-url https://pypi.org/simple/
python create-pptx/extract_assets.py <path-to-nubank-presentation.pptx>
```

This extracts the Nu logo, section logo, and cover decoration image into `create-pptx/assets/`.

## Updating

When skills are updated, just `git pull` to get the latest version:

```bash
cd identity-fraud-skills
git pull
```

Since the skills are symlinked, Cursor picks up changes automatically.
