'use client';

import { ReactNode, useEffect } from 'react';

type Props={
  open:boolean;
  title:string;
  subtitle?:string;
  icon?:string;
  tone?:'default'|'danger'|'success';
  onClose:()=>void;
  children:ReactNode;
  footer?:ReactNode;
  width?:'sm'|'md'|'lg';
};

export function CareModal({open,title,subtitle,icon='fa-pen-to-square',tone='default',onClose,children,footer,width='md'}:Props){
  useEffect(()=>{
    if(!open)return;
    const onKey=(e:KeyboardEvent)=>{if(e.key==='Escape')onClose()};
    document.addEventListener('keydown',onKey);
    const previous=document.body.style.overflow;
    document.body.style.overflow='hidden';
    return ()=>{document.removeEventListener('keydown',onKey);document.body.style.overflow=previous};
  },[open,onClose]);
  if(!open)return null;
  return <div className="care-modal-backdrop" role="presentation" onMouseDown={e=>{if(e.currentTarget===e.target)onClose()}}>
    <section className={`care-modal care-modal-${width} care-modal-${tone}`} role="dialog" aria-modal="true" aria-labelledby="care-modal-title">
      <header className="care-modal-head">
        <div className="care-modal-title-wrap"><span className="care-modal-icon"><i className={`fa-solid ${icon}`}/></span><div><h2 id="care-modal-title">{title}</h2>{subtitle&&<p>{subtitle}</p>}</div></div>
        <button type="button" className="care-modal-close" aria-label="Close" onClick={onClose}><i className="fa-solid fa-xmark"/></button>
      </header>
      <div className="care-modal-body">{children}</div>
      {footer&&<footer className="care-modal-footer">{footer}</footer>}
    </section>
  </div>
}
