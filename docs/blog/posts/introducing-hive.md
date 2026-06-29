---
title: Introducing Hive
description: Why we are building Hive. The cost of building product collapsed, harnesses are reshaping the work, and we wanted a place to do it in the open and own it.
date: 2026-06-26
author: Tuist
sidebar: false
aside: false
tags:
  - product
  - open-source
  - agents
---

# Introducing Hive

_By Tuist on June 26, 2026_

We did not set out to build Hive because we wanted another tool. We set out because LLMs reopened a question we had quietly given up on: how do we actually want to build product, and what would the thing that supports that look like?

When some of us worked at [Shopify](https://shopify.com), the part that stuck was how they treated internal tooling. Most companies reach for whatever the market is selling, Jira, the CRM of the month, the tracker everyone uses, and then bend themselves around someone else's opinion of how work should happen. Shopify did the reverse. They decided how they wanted to operate, and then built the tools that supported it. That always read as a luxury reserved for companies with that kind of headcount. For a team our size it was simply not affordable.

That equation flipped. The cost of writing code is at a historic low. The cost of running and scaling it is at a historic low. The cost of designing an interface that does not feel hostile, when you can lean on a design system and a coding agent, is at a historic low. And the foundations we had already paid for while building [Tuist](https://tuist.dev) as a business, a design system, the muscle to deploy, run, and scale services, the observability underneath, meant the gap between how we want to build product and a tool that embodies it had almost closed. Hive is what we built in that gap.

## The work is changing shape

The second thing we saw was harnesses. Not the model on its own, the scaffolding around it. A harness can take a reported error and come back with a diagnosis. It can take a spec and turn it into a reviewable change. It can read someone else's change and have an opinion worth your time. None of that is science fiction anymore. The pieces are on the shelf, it is a matter of composing them. The agentic workflows in Hive run on [Condukt](https://github.com/tuist/condukt), the Elixir framework we open sourced for exactly this.

Which means our job is changing. We think the role of a software engineer over the next few years looks less like typing the implementation and more like deciding what should exist, shaping it, and judging the result. We would rather take the lead on that than have it happen to us. So we are designing how we want to work first, and building Hive around that decision, to get the most out of the few people we have, and to raise both the quality and the bandwidth of everyone's work.

## Work with the garage door up

There was one more thing we noticed when we sketched the solution. We have always been an open company. Tuist started as open source, and most of what we do still happens in the open. It felt wrong to build the system that shapes our product behind a closed door.

Andy Matuschak keeps a note, borrowed from Robin Sloan, about [working with the garage door up](https://notes.andymatuschak.org/Work_with_the_garage_door_up). The image is a woodworker who props the shop door open while he works, so anyone walking past sees the thing being made, not just the finished piece in the window. That is the posture we want for how we build product.

So we asked a different question. What if the framework let people take a front-row seat as an idea or a bug travels from just that, an idea or a bug, to something released? And what if they could step in along the way?

We are honest about what that participation looks like now. We do not see people contributing code as actively as they once did, and that gap will widen as harnesses absorb more of the implementation. But shaping is a different act from coding. We very much see people taking a participatory role in shaping the product, weighing in on a spec, arguing for a direction, catching the thing that is about to go wrong. The door stays up, and the interesting conversation moves back to where it always mattered.

## It should be owned by us

Every platform is trying to become the tool for everything. Watch [Linear](https://linear.app) grow from an issue tracker into something that wants to hold your documents, your projects, your initiatives, your whole product process. It is a good product, and that is exactly why the pull is so strong. The more of your process lives inside one vendor, the less of it you own.

We would rather not hand that over. How we shape product, and how we make it happen, is not a generic workflow to be rented. It is one of the more specific things about a company, and it should belong to the company. Our information and our process should not scatter across a dozen tools that each want to be the center of gravity.

Hive is our take on that, and it is also a gift. It is open source for any organization that likes the way we operate and would like to operate the same way. We are not trying to sell you our opinion of how work should happen. We are showing our work with the door up, and handing you the thing we built so you can shape your own.

There has never been a better time to own how you build. That is why we are building Hive.
