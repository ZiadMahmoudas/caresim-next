import Image from 'next/image';
import { Brand } from '@/components/Brand';
import { LoginForm } from '@/components/LoginForm';

type PageProps = {
  searchParams?: Promise<{ next?: string | string[] }>;
};

export default async function Login({ searchParams }: PageProps) {
  const params = searchParams ? await searchParams : {};
  const nextPath = Array.isArray(params.next) ? params.next[0] ?? '' : params.next ?? '';

  return (
    <main className="auth-page">
      <section className="auth-panel">
        <Brand />
        <div className="auth-copy">
          <span className="eyebrow simple">CareSim Academy</span>
          <h1>Welcome back.</h1>
          <p>Continue building safe, confident clinical decision-making.</p>
        </div>
        <LoginForm nextPath={nextPath} />
        <small className="auth-note">University SSO can be enabled in production.</small>
      </section>
      <section className="auth-image">
        <Image src="https://images.unsplash.com/photo-1631217868264-e5b90bb7e133?auto=format&fit=crop&w=1400&q=85" alt="Clinical education" fill sizes="55vw" />
        <div className="image-overlay">
          <div className="quote-mark">“</div>
          <blockquote>CareSim gives learners a safe place to make decisions, see consequences and learn from every attempt.</blockquote>
          <div className="quote-person">
            <span className="avatar rose">CS</span>
            <div><b>Clinical Simulation</b><small>Practice without patient risk</small></div>
          </div>
        </div>
      </section>
    </main>
  );
}
