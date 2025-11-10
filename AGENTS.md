# CLAUDE.md

This file provides guidance to AI agents, Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

Beelievers Kickstarter is a decentralized crowdfunding and incubation platform with a token distribution mechanism, built on Sui blockchain. It's designed to launch and accelerate the next generation of innovative projects from _DeFi and beyond_.

Stack: Sui blockchain
Programming Language: Sui Move
Project specification: @spec.md

Learn about Sui Move: https://move-book.com/reference

## Repository Structure

This is a Sui Move project

```
├── Makefile
├── Move.lock
├── Move.toml     # project config file
├── sources
│   ├── pod.move  # project implementation
├── spec.md       # project spec
└── tests         # directory for tests
```

## Common Commands

```sh
# build project
make build

# run tests
make test
```
