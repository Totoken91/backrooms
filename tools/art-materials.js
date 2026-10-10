'use strict';
/* Authored procedural finishes. No fetched images, canvas or random state.
 * Atlas: 1024² / 4×4 materials / 256² cells, with 8px wrapped gutters.
 * GLSL UV = (vec2(mod(id,4.),floor(id/4.))*256. + 8. + fract(uv)*240.)/1024.
 * Surface RGB: tangent normal XYZ encoded [0,1]; A: perceptual roughness.
 * Texture V increases with the generated row. Use the same tangent basis as UV.
 * Wrapped gutters keep bilinear filtering inside each authored finish.
 */
(() => {
  const SIZE=1024,TILE=256,PAD=8,INNER=240,COUNT=16;
  const clampByte=v=>Math.max(0,Math.min(255,Math.round(v)));
  const names=Object.freeze(['yellow wallpaper','loop pile carpet','acoustic ceiling','beige skirting','prismatic diffuser','aged honey wood','dull woven fabric','painted metal','CRT glass','old vinyl','cream plaster','canvas','paper','cardboard','entity skin','cloud wallpaper']);
  const cache=new WeakMap();
  function randomAt(x,y,seed) {
    let h=Math.imul(x+seed,374761393)^Math.imul(y-seed,668265263);
    h=Math.imul(h^(h>>>13),1274126177);
    return ((h^(h>>>16))>>>0)/4294967295;
  }
  function field(period,seed) {
    const out=new Float32Array(INNER*INNER),grid=new Float32Array(period*period);
    for(let y=0;y<period;y++)for(let x=0;x<period;x++)grid[y*period+x]=randomAt(x,y,seed);
    const index=new Uint8Array(INNER),weight=new Float32Array(INNER);
    for(let x=0;x<INNER;x++){const p=x*period/INNER,f=p-Math.floor(p);index[x]=Math.floor(p);weight[x]=f*f*(3-2*f);}
    for(let y=0;y<INNER;y++){
      const y0=index[y],y1=(y0+1)%period,wy=weight[y];
      for(let x=0;x<INNER;x++){
        const x0=index[x],x1=(x0+1)%period,wx=weight[x];
        const a=grid[y0*period+x0],b=grid[y0*period+x1],c=grid[y1*period+x0],d=grid[y1*period+x1];
        out[y*INNER+x]=(a+(b-a)*wx)*(1-wy)+(c+(d-c)*wx)*wy;
      }
    }
    return out;
  }
  function generate() {
    const color=new Uint8Array(SIZE*SIZE*4),surface=new Uint8Array(SIZE*SIZE*4);
    const broad=field(3,72),mottle=field(12,348),small=field(40,982),long=field(7,663);
    const grain=new Float32Array(INNER*INNER);
    for(let y=0;y<INNER;y++)for(let x=0;x<INNER;x++)grain[y*INNER+x]=randomAt(x,y,419)-.5;
    const wave=new Float32Array(INNER),thread=new Float32Array(INNER);
    for(let x=0;x<INNER;x++){wave[x]=Math.sin(x*Math.PI*2/INNER);thread[x]=Math.sin(x*Math.PI*2/3);}
    const rgbs=Array.from({length:COUNT},()=>new Uint8Array(INNER*INNER*3)),
      heightMaps=Array.from({length:COUNT},()=>new Float32Array(INNER*INNER)),
      roughMaps=Array.from({length:COUNT},()=>new Uint8Array(INNER*INNER));
    for(let y=0;y<INNER;y++)for(let x=0;x<INNER;x++){
      const i=y*INNER+x,g=grain[i],n=mottle[i]-.5,b=broad[i]-.5,s=small[i]-.5;
      for(let material=0;material<COUNT;material++){
        const rgb=rgbs[material],heights=heightMaps[material],rough=roughMaps[material];
        let r=0,green=0,blue=0,h=128,roughness=245;
        if(material===0){
          // The faded blue-grey print belongs to the paper, not to a screen overlay.
          const column=Math.floor(x/120),cx=x%120-60,cy=(y+column*60)%120;
          const line=Math.min(Math.abs(cx-39),Math.abs(cx-42),Math.abs(cx+39),Math.abs(cx+42));
          const crest=38+Math.abs(cx)*.54;
          const chevron=Math.abs(cx)<25&&Math.min(Math.abs(cy-crest),Math.abs(cy-crest-7))<1.15;
          const print=chevron?.18:0,stripe=Math.max(0,1-line/2.5),band=wave[(x*2+60)%INNER]*1.4;
          const shade=1+b*.025+n*.015+g*.012;
          r=(208*(1-print)+132*print+stripe*5+band)*shade;
          green=(186*(1-print)+139*print+stripe*5+band)*shade;
          blue=(124*(1-print)+121*print+stripe*7+band)*shade;
          h=128+g*2.2+s+print*.8;roughness=239+g*10;
        } else if(material===1){
          // Interlocking loops, with fibre colour changing within each tuft.
          const lx=x%4-1.5,ly=y%4-1.5;
          const loop=Math.max(0,1-Math.abs(Math.sqrt(lx*lx*.62+ly*ly)-1.25)*1.8);
          const tuft=randomAt(x>>2,y>>2,311)-.5;
          const value=1+b*.04+n*.035+tuft*.04+g*.055+(loop-.45)*.04;
          r=164*value;green=151*value;blue=103*value;
          h=128+loop*5.5+g*1.5+tuft*2;roughness=250+g*8;
        } else if(material===2){
          // Porous mineral fibre; the architectural ceiling grid is geometry/shader.
          const pore=(g<-.39?(-.39-g)*135:0)+Math.max(0,-s-.22)*19;
          const fibre=grain[y*INNER+(x+Math.floor(y/3))%INNER]>.465?1.82:0;
          const value=1+b*.0126+n*.0119+g*.0105;
          r=218*value-pore-fibre;green=216*value-pore-fibre;blue=192*value-pore-fibre;
          h=128+g*1.68-pore*.5;roughness=247+g*7;
        } else if(material===3){
          const value=1+b*.025+n*.025+g*.018;
          r=153*value;green=145*value;blue=108*value;
          h=128+g*1.0;roughness=218+g*10;
        } else if(material===4){
          const prism=(x%3===0?1:0)+(y%3===0?1:0),dust=long[i];
          r=238-prism*3-dust*6;green=236-prism*3-dust*6;blue=213-prism*3-dust*5;
          h=128+prism*2;roughness=176+g*5;
        } else if(material===5){
          const shifted=(x+Math.round(wave[y]*2)+INNER)%INNER;
          const bands=long[(y%30)*INNER+shifted],fibre=grain[(y%7)*INNER+x];
          const value=.87+bands*.24+n*.045+fibre*.065;
          r=144*value;green=106*value;blue=60*value;
          h=128+fibre*2.5+bands*2;roughness=224+g*12;
        } else if(material===6||material===11){
          const weave=(thread[x]+thread[y])*.5,value=1+b*.055+n*.05+g*.055+weave*.035;
          r=(material===6?104:147)*value;green=(material===6?110:151)*value;blue=(material===6?89:117)*value;
          h=128+weave*2.8+g*1.5;roughness=249+g*7;
        } else if(material===7){
          const value=1+n*.025+g*.012;
          r=167*value;green=166*value;blue=146*value;
          h=128+g*.8;roughness=188+g*8+n*5;
        } else if(material===8){
          r=20+g*1.3;green=28+g*1.5;blue=23+g*1.3;h=128;roughness=105;
        } else if(material===9){
          const fleck=g>.455?7:g<-.45?-7:0,value=1+b*.035+n*.04;
          r=157*value+fleck;green=150*value+fleck;blue=115*value+fleck;
          h=128+g*1.5;roughness=210+n*8+g*5;
        } else if(material===10){
          const value=1+b*.025+n*.016+g*.014;
          r=213*value;green=205*value;blue=166*value;
          h=128+g*1.5+s*.5;roughness=241+g*6;
        } else if(material===12){
          const value=1+b*.035+g*.018;
          r=188*value;green=177*value;blue=139*value;
          h=128+g*1.0;roughness=244+g*4;
        } else if(material===13){
          const value=1+b*.035+n*.035+g*.04;
          r=154*value;green=130*value;blue=86*value;
          h=128+g*2;roughness=247+g*6;
        } else if(material===14){
          r=21+n*8+g*3;green=24+n*8+g*3;blue=19+n*7+g*3;
          h=128+s*4+g*2;roughness=238+g*10;
        } else {
          const u=(x+(Math.floor(y/120)%2)*60)%120/120,v=y%120/120;
          const ellipse=(cx,cy,rx,ry)=>((u-cx)/rx)**2+((v-cy)/ry)**2;
          const edge=Math.min(ellipse(.50,.48,.31,.15),ellipse(.33,.48,.16,.13),ellipse(.48,.59,.17,.21),ellipse(.67,.49,.18,.14));
          const cloud=Math.max(0,Math.min(1,(1.04-edge)*15)),value=1+n*.025+g*.018;
          r=(101+(221-101)*cloud)*value;green=(155+(219-155)*cloud)*value;blue=(182+(194-182)*cloud)*value;
          h=128+g*3+s;roughness=240+g*7;
        }
        const p=i*3;rgb[p]=clampByte(r);rgb[p+1]=clampByte(green);rgb[p+2]=clampByte(blue);
        heights[i]=h;rough[i]=clampByte(roughness);
      }
    }
    for(let material=0;material<COUNT;material++){
      const rgb=rgbs[material],heights=heightMaps[material],rough=roughMaps[material];
      const tileX=(material%4)*TILE,tileY=Math.floor(material/4)*TILE;
      for(let y=0;y<TILE;y++)for(let x=0;x<TILE;x++){
        const sx=(x-PAD+INNER)%INNER,sy=(y-PAD+INNER)%INNER,i=sy*INNER+sx;
        const left=sy*INNER+(sx+INNER-1)%INNER,right=sy*INNER+(sx+1)%INNER;
        const down=((sy+INNER-1)%INNER)*INNER+sx,up=((sy+1)%INNER)*INNER+sx;
        // Finishes are nearly flat: subtle glancing response rather than relief.
        const nx=(heights[left]-heights[right])*.034,ny=(heights[down]-heights[up])*.034;
        const inv=1/Math.sqrt(1+nx*nx+ny*ny),p=((tileY+y)*SIZE+tileX+x)*4,c=i*3;
        color[p]=rgb[c];color[p+1]=rgb[c+1];color[p+2]=rgb[c+2];color[p+3]=255;
        surface[p]=clampByte((nx*inv*.5+.5)*255);surface[p+1]=clampByte((ny*inv*.5+.5)*255);
        surface[p+2]=clampByte((inv*.5+.5)*255);surface[p+3]=rough[i];
      }
    }
    return {color,surface};
  }
  function create(gl) {
    if(cache.has(gl))return cache.get(gl);
    const maps=generate();
    const upload=data=>{
      const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,SIZE,SIZE,0,gl.RGBA,gl.UNSIGNED_BYTE,data);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      return texture;
    };
    const result=Object.freeze({color:upload(maps.color),surface:upload(maps.surface)});
    cache.set(gl,result);return result;
  }
  globalThis.OutOfFrameMaterials=Object.freeze({create,generate,SIZE,TILE,PAD,INNER,names});
})();
