import { Component, type ReactNode } from 'react';

/// Last line of defence: if drawing the planner throws, show what happened and a way back instead of
/// a blank page. Projects are already saved in this browser; nothing here deletes them.
export class ErrorBoundary extends Component<{ children: ReactNode }, { error?: Error }> {
  state: { error?: Error } = {};

  /// Anything can be thrown, even null: keep an Error so the screen always shows.
  static getDerivedStateFromError(thrown: unknown) {
    return { error: thrown instanceof Error ? thrown : new Error(String(thrown)) };
  }

  componentDidCatch(thrown: unknown) { console.error('FrameScan planner crashed', thrown); }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <main className="crash" role="alert" style={{ maxWidth: '34em', margin: '15vh auto', padding: '0 16px' }}>
        <h1>Something went wrong</h1>
        <p>The planner hit a problem it couldn't recover from. Your projects are still saved in this browser.</p>
        <p><code>{error.message}</code></p>
        <p>
          <button className="btn" onClick={() => { this.setState({ error: undefined }); }}>Try again</button>{' '}
          <button className="btn" onClick={() => window.location.reload()}>Reload</button>
        </p>
      </main>
    );
  }
}
