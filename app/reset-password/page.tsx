import { Suspense } from 'react';
import { Brand } from '@/components/Brand';
import { ResetPasswordForm } from '@/components/ResetPasswordForm';

function ResetPasswordFallback() {
  return (
    <div className="auth-form">
      <div className="form-message">Loading secure reset form…</div>
    </div>
  );
}

export default function ResetPasswordPage() {
  return (
    <main className="auth-centered">
      <div className="auth-centered-card">
        <Brand />
        <span className="eyebrow simple">Secure account</span>
        <h1>Choose a new password.</h1>
        <p>Use a strong password you don’t reuse elsewhere.</p>

        <Suspense fallback={<ResetPasswordFallback />}>
          <ResetPasswordForm />
        </Suspense>
      </div>
    </main>
  );
}
