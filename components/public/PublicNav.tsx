'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';
import { Brand } from '@/components/Brand';

const links=[['/','Home'],['/about','About'],['/contact','Contact']];
export function PublicNav(){
  const path=usePathname(); const [open,setOpen]=useState(false);
  return <>
    <header className="public-header"><nav className="public-nav">
      <div onClick={()=>setOpen(false)}><Brand/></div>
      <div className={`public-links ${open?'open':''}`}>{links.map(([href,label])=><Link key={href} href={href} onClick={()=>setOpen(false)} className={path===href?'active':''}>{label}</Link>)}<Link href="/login" onClick={()=>setOpen(false)} className="mobile-public-login">Sign in</Link></div>
      <div className="public-actions"><Link href="/login" className="btn ghost public-signin">Sign in</Link><Link href="/register" className="btn primary">Create account</Link><button className="public-menu" onClick={()=>setOpen(v=>!v)} aria-label="Toggle menu"><i className={`fa-solid ${open?'fa-xmark':'fa-bars'}`}/></button></div>
    </nav></header>
    {open&&<button className="public-menu-overlay" onClick={()=>setOpen(false)} aria-label="Close menu"/>}
  </>
}
