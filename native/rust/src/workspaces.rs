//! Platform-neutral workspace hierarchy and reconciliation.
//!
//! Mobile clients consume remote-only snapshots. Desktop clients may also
//! provide local snapshots, which are reconciled by stable server identifiers
//! while retaining local repository and worktree locations.

use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WorkspacePresence {
    Local,
    Remote,
    LocalAndRemote,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RemoteWorkspaceEndpoint {
    HiveServer,
    NearbyMac { id: String, name: String },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorkspaceSnapshot {
    pub id: String,
    pub name: String,
    pub presence: WorkspacePresence,
    pub projects: Vec<ProjectSnapshot>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProjectSnapshot {
    pub id: String,
    pub name: String,
    pub presence: WorkspacePresence,
    pub local_repository: Option<PathBuf>,
    pub sessions: Vec<SessionSnapshot>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SessionSnapshot {
    pub id: String,
    pub title: String,
    pub presence: WorkspacePresence,
    pub local_worktree: Option<PathBuf>,
}

/// Source boundary for the Hive-hosted hierarchy. The server-backed
/// implementation can replace a local fixture without changing platform code.
pub trait RemoteWorkspaceSource {
    type Error;

    fn load(
        &self,
        endpoint: &RemoteWorkspaceEndpoint,
    ) -> Result<Vec<WorkspaceSnapshot>, Self::Error>;
}

/// Reconciles desktop-local state with the hierarchy owned by the Hive server.
/// Remote names are canonical while local filesystem locations are preserved.
pub fn reconcile_workspaces(
    local: Vec<WorkspaceSnapshot>,
    remote: Vec<WorkspaceSnapshot>,
) -> Vec<WorkspaceSnapshot> {
    let mut workspaces = local
        .into_iter()
        .map(|workspace| (workspace.id.clone(), workspace))
        .collect::<BTreeMap<_, _>>();

    for remote_workspace in remote {
        if let Some(local_workspace) = workspaces.remove(&remote_workspace.id) {
            workspaces.insert(
                remote_workspace.id.clone(),
                WorkspaceSnapshot {
                    id: remote_workspace.id,
                    name: remote_workspace.name,
                    presence: WorkspacePresence::LocalAndRemote,
                    projects: reconcile_projects(
                        local_workspace.projects,
                        remote_workspace.projects,
                    ),
                },
            );
        } else {
            workspaces.insert(remote_workspace.id.clone(), remote_workspace);
        }
    }

    workspaces.into_values().collect()
}

fn reconcile_projects(
    local: Vec<ProjectSnapshot>,
    remote: Vec<ProjectSnapshot>,
) -> Vec<ProjectSnapshot> {
    let mut projects = local
        .into_iter()
        .map(|project| (project.id.clone(), project))
        .collect::<BTreeMap<_, _>>();

    for remote_project in remote {
        if let Some(local_project) = projects.remove(&remote_project.id) {
            projects.insert(
                remote_project.id.clone(),
                ProjectSnapshot {
                    id: remote_project.id,
                    name: remote_project.name,
                    presence: WorkspacePresence::LocalAndRemote,
                    local_repository: local_project.local_repository,
                    sessions: reconcile_sessions(local_project.sessions, remote_project.sessions),
                },
            );
        } else {
            projects.insert(remote_project.id.clone(), remote_project);
        }
    }

    projects.into_values().collect()
}

fn reconcile_sessions(
    local: Vec<SessionSnapshot>,
    remote: Vec<SessionSnapshot>,
) -> Vec<SessionSnapshot> {
    let mut sessions = local
        .into_iter()
        .map(|session| (session.id.clone(), session))
        .collect::<BTreeMap<_, _>>();

    for remote_session in remote {
        if let Some(local_session) = sessions.remove(&remote_session.id) {
            sessions.insert(
                remote_session.id.clone(),
                SessionSnapshot {
                    id: remote_session.id,
                    title: remote_session.title,
                    presence: WorkspacePresence::LocalAndRemote,
                    local_worktree: local_session.local_worktree,
                },
            );
        } else {
            sessions.insert(remote_session.id.clone(), remote_session);
        }
    }

    sessions.into_values().collect()
}
