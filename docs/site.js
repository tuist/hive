const docsSidebar = [
  {
    text: "Getting started",
    items: [
      { text: "Overview", link: "/guide/self-hosting/" },
      { text: "Install Hive", link: "/guide/self-hosting/installation" },
      { text: "Authentication", link: "/guide/self-hosting/authentication" },
      { text: "Authorization", link: "/guide/self-hosting/authorization" },
    ],
  },
  {
    text: "Using Hive",
    items: [
      { text: "Projects", link: "/guide/using-hive/projects" },
      { text: "Domains", link: "/guide/using-hive/domains" },
      { text: "Forage", link: "/guide/using-hive/forage" },
      { text: "Flights", link: "/guide/using-hive/flights" },
      { text: "Specs", link: "/guide/using-hive/specs" },
      { text: "Drops", link: "/guide/self-hosting/drops" },
    ],
  },
  {
    text: "Integrations",
    items: [
      { text: "GitHub", link: "/guide/self-hosting/github" },
      { text: "Slack", link: "/guide/self-hosting/slack" },
      { text: "Model gateway", link: "/guide/self-hosting/inference" },
    ],
  },
  {
    text: "Operations",
    items: [
      { text: "Deployment options", link: "/guide/self-hosting/deployment" },
      { text: "Audit", link: "/guide/self-hosting/audit" },
    ],
  },
  {
    text: "Reference",
    items: [
      { text: "Configuration", link: "/reference/configuration" },
      { text: "Application programming interface", link: "/reference/api" },
      { text: "Feeds", link: "/reference/feeds" },
    ],
  },
];

export const site = {
  description:
    "Hive connects product signals, shared specs, and shipped work in one self-hosted service.",
  nav: [
    { text: "Docs", link: "/" },
    { text: "Blog", link: "/blog/" },
    {
      text: "Project",
      items: [
        {
          text: "Releases",
          link: "https://github.com/tuist/hive/releases",
        },
        {
          text: "Report an issue",
          link: "https://github.com/tuist/hive/issues",
        },
        {
          text: "Open Tuist's Hive",
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
    message: "Released under the Mozilla Public License 2.0.",
    copyright: "Copyright © Tuist GmbH",
  },
};
