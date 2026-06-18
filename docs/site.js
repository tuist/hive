export const site = {
  description:
    "Hive is Tuist's agentic meadow orchestration platform: spec-driven planning, forage ingestion, and self-hostable deployment.",
  nav: [
    { text: "Docs", link: "/" },
    {
      text: "Links",
      items: [
        {
          text: "Releases",
          link: "https://github.com/tuist/hive/releases",
        },
        {
          text: "Issues",
          link: "https://github.com/tuist/hive/issues",
        },
        {
          text: "hive.tuist.dev",
          link: "https://hive.tuist.dev",
        },
      ],
    },
  ],
  sidebar: {
    "/": [
      { text: "Why Hive", link: "/guide/why" },
      {
        text: "Self-hosting",
        collapsed: false,
        items: [
          { text: "Overview", link: "/guide/self-hosting/" },
          { text: "Authentication", link: "/guide/self-hosting/authentication" },
          { text: "Agents", link: "/guide/self-hosting/agents" },
          { text: "Audit", link: "/guide/self-hosting/audit" },
          { text: "Slack", link: "/guide/self-hosting/slack" },
          { text: "Deployment", link: "/guide/self-hosting/deployment" },
        ],
      },
    ],
  },
  footer: {
    message: "Released under the MPL-2.0 License.",
    copyright: "Copyright © Tuist GmbH",
  },
};
