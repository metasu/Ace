---
name: engineering-standards-curation
description: "Use when consolidating, splitting, simplifying, or maintaining a family of engineering standards documents, especially a shared cross-machine standard plus machine-specific baselines. Covers ownership boundaries, deduplication, preserving operational detail, cross-reference migration, versioning, and mechanical validation."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [documentation, standards, curation, deduplication, baselines]
    related_skills: [technical-writing, humanizer]
---

# Engineering Standards Curation

## Purpose

Maintain engineering guidance as a small set of class-level documents with clear ownership rather than a growing pile of overlapping notes. The usual shape is:

- one shared standard for stable, cross-machine methods;
- one baseline per machine or environment for paths, versions, local services, and reproducible local quirks;
- optional reference files for detailed evidence or long recipes that should not dominate the main standard.

A successful simplification reduces repetition and retrieval cost without deleting the commands, validation criteria, safety constraints, or failure recovery steps that make the standards useful.

## When to Use

Use this skill when asked to:

- consolidate or simplify two or more engineering guidance files;
- split common rules from host-specific facts;
- remove duplicated checklists or troubleshooting sections;
- reorganize a standards library without breaking links;
- update machine baselines after installing or changing tools;
- turn accumulated session notes into durable class-level guidance.

Do not use it for ordinary prose shortening where there is no standards hierarchy or operational contract.

## Ownership Model

### Shared standard owns

- evidence and verification principles;
- modification and safety boundaries;
- configuration and credential handling;
- shell, encoding, writing, debugging, and delivery methods;
- cross-machine tool selection rules;
- generic acceptance criteria and stable failure patterns.

### Machine baseline owns

- host identity, workspaces, drive letters, and absolute paths;
- installed versions and validated component state;
- local proxy endpoints and local service locations;
- machine-specific tool choice and environment selection;
- reproducible filesystem, terminal, driver, or sync-volume quirks;
- short commands needed to enter or verify that machine's environment.

### Reference files own

- long reproduction transcripts;
- historical evidence snapshots;
- detailed one-tool recipes that are useful but too large for the primary standard;
- migration maps and audit notes.

If a statement contains both a universal rule and a host-specific value, split it: put the rule in the shared standard and the concrete path/version in the baseline, with one concise cross-reference.

## Workflow

### 1. Read the complete document family

Read every file that links to or is linked from the target documents. Capture:

- headings and section numbers;
- front matter names, versions, tags, and related skills;
- links and explicit section references;
- duplicated rules, commands, checklists, and troubleshooting entries;
- contradictions and stale snapshots.

Do not rewrite from excerpts. A local section-number change can break sibling baselines that were not named in the initial request.

### 2. Build a responsibility map

Classify each substantive item as one of:

- shared rule;
- machine fact;
- detailed reference;
- duplicate;
- stale or unsupported claim.

For duplicates, select the strongest version: the one with a trigger, exact action, validation, and safety boundary. Merge missing details into that owner instead of keeping two paraphrases.

### 3. Define preservation invariants

Before editing, list information that must survive. Typical invariants include:

- credential redaction and source-of-truth rules;
- exact environment activation commands;
- framework or compiler compatibility boundaries;
- local proxy scope and protocol checks;
- build/test/media acceptance criteria;
- known machine-specific filesystem recovery paths;
- links to all sibling standards.

Line-count reduction is secondary to these invariants.

### 4. Consolidate by retrieval path

Organize around what an engineer needs to find:

1. scope and entry point;
2. core workflow and safety rules;
3. domain-specific operating standards;
4. failure lookup;
5. final verification and maintenance boundary.

For machine baselines, prefer compact version/path tables followed by only the commands and exceptions needed to use them. Avoid repeating generic commands already owned by the shared standard.

### 5. Version intentionally

Use a major version increase when ownership, section layout, or cross-document contracts change substantially. Use a minor increase for additive facts or localized restructuring. Keep snapshot dates beside volatile package/framework versions and explicitly require live revalidation.

### 6. Repair the whole reference graph

After headings change, search every related standards file for:

- old section numbers;
- old headings;
- relative links to the rewritten documents;
- descriptions that enumerate removed sections;
- checklist pointers that now land in the wrong place.

Patch sibling files only as needed to preserve valid references; do not opportunistically rewrite their content.

### 7. Validate mechanically and semantically

Mechanical checks:

- files and linked siblings exist;
- front matter opens/closes and versions changed as intended;
- Markdown code fences are balanced;
- headings are unique and ordered;
- obsolete section references have zero matches;
- key terms and preservation invariants remain searchable;
- line/byte counts show the actual reduction.

Semantic checks:

- shared and machine documents no longer duplicate ownership;
- commands still identify the intended shell;
- version snapshots are labeled as snapshots, not permanent latest versions;
- a reader can move from shared method to local path without guessing;
- no security or validation requirement disappeared during compression.

## Communication

Report:

- which files changed and their new versions;
- the new ownership boundary;
- measurable before/after size;
- major duplicate groups removed;
- sibling files touched only for reference repair;
- validation performed and any residual ambiguity.

Do not claim success based only on visual inspection. Include mechanical evidence such as fence counts, zero stale-reference matches, and file/link existence.

## Pitfalls

1. **Optimizing only for fewer lines.** Dense prose can be harder to retrieve and may hide lost safety constraints.
2. **Rewriting only the two named files.** Sibling baselines may retain stale section references.
3. **Copying universal commands into every machine file.** Keep one owner and cross-reference it.
4. **Moving local paths into the shared standard.** This makes a cross-machine rule silently machine-dependent.
5. **Deleting repeated text before choosing an owner.** First preserve the strongest operational version.
6. **Keeping unexplained version claims.** Label volatile versions with observation dates and require live checks.
7. **Leaving long forensic recipes inline.** Move them to `references/` and retain a short trigger and pointer.
8. **Changing sibling content while repairing links.** Keep graph repair narrow.

## Verification Checklist

- [ ] Complete target and sibling document family inspected
- [ ] Each rule has one clear owner
- [ ] Preservation invariants recorded and retained
- [ ] Common rules and host facts separated
- [ ] Front matter and versions updated intentionally
- [ ] All old section references searched across the family
- [ ] Links resolve and code fences are balanced
- [ ] Key safety, recovery, and acceptance criteria remain searchable
- [ ] Before/after line and byte counts recorded
- [ ] Final report distinguishes requested rewrites from sibling link repairs

## References

- `references/common-and-machine-baseline-consolidation.md` - concrete audit matrix, consolidation decisions, and validation probes for a shared standard plus Windows machine baseline.
