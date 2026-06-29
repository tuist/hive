const docsSidebar = [
  {
    text: "Guide",
    items: [
      { text: "Overview", link: "/guide/self-hosting/" },
      { text: "Authentication", link: "/guide/self-hosting/authentication" },
      { text: "Authorization", link: "/guide/self-hosting/authorization" },
      { text: "Model gateway", link: "/guide/self-hosting/inference" },
      { text: "Audit", link: "/guide/self-hosting/audit" },
      { text: "Drops", link: "/guide/self-hosting/drops" },
      { text: "Slack", link: "/guide/self-hosting/slack" },
      { text: "Deployment", link: "/guide/self-hosting/deployment" },
    ],
  },
  {
    text: "References",
    items: [
      { text: "Configuration", link: "/reference/configuration" },
    ],
  },
];

export const site = {
  description:
    "Hive is Tuist's agentic domain orchestration platform: spec-driven planning, forage ingestion, and self-hostable deployment.",
  nav: [
    { text: "Docs", link: "/" },
    { text: "Blog", link: "/blog/" },
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
    "/guide/": docsSidebar,
    "/reference/": docsSidebar,
  },
  footer: {
    message: "Released under the MPL-2.0 License.",
    copyright: "Copyright © Tuist GmbH",
  },
};
