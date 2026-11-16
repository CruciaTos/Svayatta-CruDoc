import{$t as e,C as t,D as n,E as r,F as i,Hn as a,I as o,In as s,Jn as c,Jt as l,L as u,M as d,Mt as f,N as p,O as m,P as h,Qt as g,R as _,Rn as v,S as y,St as b,Xn as ee,Xt as x,Y as S,Yn as te,Yt as C,a as w,b as T,c as E,dr as D,f as ne,fr as re,g as ie,it as O,jt as k,k as A,l as ae,lr as j,n as oe,o as se,qt as ce,s as le,t as M,ut as N,v as ue,w as de,x as fe,xt as pe,y as P,zn as me}from"./Geometry.js";function he(e){return e}function F(e){if(e===null||e===`null`)return null;if(e===`true`)return!0;if(e===`false`)return!1;if(e!==void 0&&e!==`undefined`)return e[0]===`[`&&e[e.length-1]===`]`?e.substring(1,e.length-1).split(`,`).map(e=>F(e.trim())):e===``||Number.isNaN(Number(e))?e:Number(e)}function ge(e=!0,t=window.location.search){let n={},r=e?F:he;return new URLSearchParams(t).forEach((e,t)=>{t&&(n[t]=!e||r(e))}),n}var _e={toNativeType:F,extractURLParameters:ge},I={States:{IS_START:0,IS_NONE:0,IS_ROTATE:1,IS_PAN:2,IS_SPIN:3,IS_DOLLY:4,IS_CAMERA_POSE:11,IS_WINDOW_LEVEL:1024,IS_SLICE:1025}},{vtkErrorMacro:ve,VOID:ye}=l;function be(e,t,n,r){return e.getRenderWindow().getViews()[0].worldToDisplay(t,n,r,e)}function xe(e,t,n,r){return e.getRenderWindow().getViews()[0].displayToWorld(t,n,r,e)}var Se={computeWorldToDisplay:be,computeDisplayToWorld:xe};function Ce(e,t){t.classHierarchy.push(`vtkInteractorObserver`);let n={...e};function r(){for(;t.subscribedEvents.length;)t.subscribedEvents.pop().unsubscribe()}function i(){se.handledEvents.forEach(n=>{e[`handle${n}`]&&t.subscribedEvents.push(t._interactor[`on${n}`](r=>t.processEvents?e[`handle${n}`](r):ye,t.priority))})}e.setInteractor=n=>{n!==t._interactor&&(r(),t._interactor=n,n&&t.enabled&&i(),e.modified())},e.setEnabled=n=>{n!==t.enabled&&(r(),n&&(t._interactor?i():ve(`
          The interactor must be set before subscribing to events
        `)),t.enabled=n,e.modified())},e.computeDisplayToWorld=(e,n,r,i)=>e?t._interactor.getView().displayToWorld(n,r,i,e):null,e.computeWorldToDisplay=(e,n,r,i)=>e?t._interactor.getView().worldToDisplay(n,r,i,e):null,e.setPriority=e=>{n.setPriority(e)&&t._interactor&&(r(),i())}}var we={enabled:!0,priority:0,processEvents:!0,subscribedEvents:[]};function L(e,t,n={}){Object.assign(t,we,n),l.obj(e,t),l.event(e,t,`InteractionEvent`),l.event(e,t,`StartInteractionEvent`),l.event(e,t,`EndInteractionEvent`),l.get(e,t,[`_interactor`,`enabled`]),l.setGet(e,t,[`priority`,`processEvents`]),l.moveToProtected(e,t,[`interactor`]),Ce(e,t)}var Te={newInstance:l.newInstance(L,`vtkInteractorObserver`),extend:L,...Se},{States:R}=I,z={Rotate:R.IS_ROTATE,Pan:R.IS_PAN,Spin:R.IS_SPIN,Dolly:R.IS_DOLLY,CameraPose:R.IS_CAMERA_POSE,WindowLevel:R.IS_WINDOW_LEVEL,Slice:R.IS_SLICE};function Ee(e,t){t.classHierarchy.push(`vtkInteractorStyle`),Object.keys(z).forEach(n=>{l.event(e,t,`Start${n}Event`),e[`start${n}`]=()=>{t.state===R.IS_NONE&&(t.state=z[n],t._interactor.requestAnimation(e),e.invokeStartInteractionEvent({type:`StartInteractionEvent`}),e[`invokeStart${n}Event`]({type:`Start${n}Event`}))},l.event(e,t,`End${n}Event`),e[`end${n}`]=()=>{t.state===z[n]&&(t.state=R.IS_NONE,t._interactor.cancelAnimation(e),e.invokeEndInteractionEvent({type:`EndInteractionEvent`}),e[`invokeEnd${n}Event`]({type:`End${n}Event`}),t._interactor.render())}}),t.getRenderer=e=>t.focusedRenderer||e.pokedRenderer,e.handleKeyPress=e=>{let n=t._interactor,r=null;switch(e.key){case`r`:case`R`:t.getRenderer(e).resetCamera(),n.render();break;case`w`:case`W`:r=t.getRenderer(e).getActors(),r.forEach(e=>{let t=e.getProperty();t.setRepresentationToWireframe&&t.setRepresentationToWireframe()}),n.render();break;case`s`:case`S`:r=t.getRenderer(e).getActors(),r.forEach(e=>{let t=e.getProperty();t.setRepresentationToSurface&&t.setRepresentationToSurface()}),n.render();break;case`v`:case`V`:r=t.getRenderer(e).getActors(),r.forEach(e=>{let t=e.getProperty();t.setRepresentationToPoints&&t.setRepresentationToPoints()}),n.render()}}}var De={state:R.IS_NONE,handleObservers:1,autoAdjustCameraClippingRange:1};function B(e,t,n={}){Object.assign(t,De,n),Te.extend(e,t,n),l.setGet(e,t,[`focusedRenderer`]),Ee(e,t)}var Oe={newInstance:l.newInstance(B,`vtkInteractorStyle`),extend:B,...I},{States:V}=I;function ke(e,t){t.classHierarchy.push(`vtkInteractorStyleTrackballCamera`),e.handleMouseMove=n=>{let r=n.position,i=t.getRenderer(n);switch(t.state){case V.IS_ROTATE:e.handleMouseRotate(i,r),e.invokeInteractionEvent({type:`InteractionEvent`});break;case V.IS_PAN:e.handleMousePan(i,r),e.invokeInteractionEvent({type:`InteractionEvent`});break;case V.IS_DOLLY:t.wheelDolly||(e.handleMouseDolly(i,r),e.invokeInteractionEvent({type:`InteractionEvent`}));break;case V.IS_SPIN:e.handleMouseSpin(i,r),e.invokeInteractionEvent({type:`InteractionEvent`})}t.previousPosition=r},e.handleButton3D=n=>{n&&n.pressed&&n.device===le.RightController&&(n.input===E.Trigger||n.input===E.TrackPad)?e.startCameraPose():n&&!n.pressed&&n.device===le.RightController&&(n.input===E.Trigger||n.input===E.TrackPad)&&t.state===V.IS_CAMERA_POSE&&e.endCameraPose()},e.handleMove3D=n=>{switch(t.state){case V.IS_CAMERA_POSE:e.updateCameraPose(n)}},e.updateCameraPose=e=>{let n=t.getRenderer(e).getActiveCamera(),r=n.getPhysicalTranslation(),i=.025*n.getPhysicalScale(),a=n.physicalOrientationToWorldDirection([e.orientation.x,e.orientation.y,e.orientation.z,e.orientation.w]);n.setPhysicalTranslation(r[0]+a[0]*i,r[1]+a[1]*i,r[2]+a[2]*i)},e.handleLeftButtonPress=n=>{t.previousPosition=n.position,n.shiftKey?n.controlKey||n.altKey?e.startDolly():e.startPan():n.controlKey||n.altKey?e.startSpin():e.startRotate()},e.handleLeftButtonRelease=()=>{switch(t.state){case V.IS_DOLLY:e.endDolly();break;case V.IS_PAN:e.endPan();break;case V.IS_SPIN:e.endSpin();break;case V.IS_ROTATE:e.endRotate()}},e.handleStartMouseWheel=()=>{t.wheelDolly=!0,e.startDolly()},e.handleEndMouseWheel=()=>{e.endDolly(),t.wheelDolly=!1},e.handleStartPinch=n=>{t.previousScale=n.scale,e.startDolly()},e.handleEndPinch=()=>{e.endDolly()},e.handleStartRotate=n=>{t.previousRotation=n.rotation,e.startRotate()},e.handleEndRotate=()=>{e.endRotate()},e.handleStartPan=n=>{t.previousTranslation=n.translation,e.startPan()},e.handleEndPan=()=>{e.endPan()},e.handlePinch=n=>{e.dollyByFactor(t.getRenderer(n),n.scale/t.previousScale),t.previousScale=n.scale},e.handlePan=n=>{let r=t.getRenderer(n).getActiveCamera(),i=r.getFocalPoint();i=e.computeWorldToDisplay(t.getRenderer(n),i[0],i[1],i[2]);let a=i[2],o=n.translation,s=t.previousTranslation,c=e.computeDisplayToWorld(t.getRenderer(n),i[0]+o[0]-s[0],i[1]+o[1]-s[1],a),l=e.computeDisplayToWorld(t.getRenderer(n),i[0],i[1],a),u=[];u[0]=l[0]-c[0],u[1]=l[1]-c[1],u[2]=l[2]-c[2],i=r.getFocalPoint();let d=r.getPosition();r.setFocalPoint(u[0]+i[0],u[1]+i[1],u[2]+i[2]),r.setPosition(u[0]+d[0],u[1]+d[1],u[2]+d[2]),t._interactor.getLightFollowCamera()&&t.getRenderer(n).updateLightsGeometryToFollowCamera(),r.orthogonalizeViewUp(),t.previousTranslation=n.translation},e.handleRotate=e=>{let n=t.getRenderer(e).getActiveCamera();n.roll(e.rotation-t.previousRotation),n.orthogonalizeViewUp(),t.previousRotation=e.rotation},e.handleMouseRotate=(e,n)=>{if(!t.previousPosition)return;let r=t._interactor,i=n.x-t.previousPosition.x,a=n.y-t.previousPosition.y,o=r.getView().getViewportSize(e),s=-.1,c=-.1;o[0]&&o[1]&&(s=-20/o[1],c=-20/o[0]);let l=i*c*t.motionFactor,u=a*s*t.motionFactor,d=e.getActiveCamera();!Number.isNaN(l)&&!Number.isNaN(u)&&(d.azimuth(l),d.elevation(u),d.orthogonalizeViewUp()),t.autoAdjustCameraClippingRange&&e.resetCameraClippingRange(),r.getLightFollowCamera()&&e.updateLightsGeometryToFollowCamera()},e.handleMouseSpin=(e,n)=>{if(!t.previousPosition)return;let r=t._interactor,i=e.getActiveCamera(),a=r.getView().getViewportCenter(e),o=k(Math.atan2(t.previousPosition.y-a[1],t.previousPosition.x-a[0])),s=k(Math.atan2(n.y-a[1],n.x-a[0]))-o;Number.isNaN(s)||(i.roll(s),i.orthogonalizeViewUp())},e.handleMousePan=(n,r)=>{if(!t.previousPosition)return;let i=n.getActiveCamera(),a=i.getFocalPoint();a=e.computeWorldToDisplay(n,a[0],a[1],a[2]);let o=a[2],s=e.computeDisplayToWorld(n,r.x,r.y,o),c=e.computeDisplayToWorld(n,t.previousPosition.x,t.previousPosition.y,o),l=[];l[0]=c[0]-s[0],l[1]=c[1]-s[1],l[2]=c[2]-s[2],a=i.getFocalPoint();let u=i.getPosition();i.setFocalPoint(l[0]+a[0],l[1]+a[1],l[2]+a[2]),i.setPosition(l[0]+u[0],l[1]+u[1],l[2]+u[2]),t._interactor.getLightFollowCamera()&&n.updateLightsGeometryToFollowCamera()},e.handleMouseDolly=(n,r)=>{if(!t.previousPosition)return;let i=r.y-t.previousPosition.y,a=t._interactor.getView().getViewportCenter(n),o=t.motionFactor*i/a[1];e.dollyByFactor(n,1.1**o)},e.handleMouseWheel=n=>{let r=1-n.spinY/t.zoomFactor;e.dollyByFactor(t.getRenderer(n),r)},e.dollyByFactor=(e,n)=>{if(Number.isNaN(n))return;let r=e.getActiveCamera();r.getParallelProjection()?r.setParallelScale(r.getParallelScale()/n):(r.dolly(n),t.autoAdjustCameraClippingRange&&e.resetCameraClippingRange()),t._interactor.getLightFollowCamera()&&e.updateLightsGeometryToFollowCamera()}}var Ae={motionFactor:10,zoomFactor:10,wheelDolly:!1};function H(e,t,n={}){Object.assign(t,Ae,n),Oe.extend(e,t,n),l.setGet(e,t,[`motionFactor`,`zoomFactor`]),ke(e,t)}var je={newInstance:l.newInstance(H,`vtkInteractorStyleTrackballCamera`),extend:H},{vtkErrorMacro:Me}=C,U=[`setBindGroup`,`setIndexBuffer`,`setVertexBuffer`,`draw`,`drawIndexed`];function Ne(e,t){t.classHierarchy.push(`vtkWebGPURenderEncoder`),e.begin=e=>{t.drawCallbacks=[],t.handle=e.beginRenderPass(t.description),t.label&&t.handle.pushDebugGroup(t.label)},e.end=()=>{for(let n=0;n<t.drawCallbacks.length;n++){let r=t.drawCallbacks[n],i=r.pipeline;e.setPipeline(i);for(let t=0;t<r.callbacks.length;t++)r.callbacks[t](e)}t.label&&t.handle.popDebugGroup(),t.handle.end(),t.boundPipeline=null},e.setPipeline=e=>{if(t.boundPipeline===e)return;t.handle.setPipeline(e.getHandle());let n=e.getPipelineDescription(),r=n.fragment?.targets;if(t.colorTextureViews.length!==r.length)console.log(`mismatched attachment counts on pipeline ${r.length} while encoder has ${t.colorTextureViews.length}`),console.trace();else for(let e=0;e<t.colorTextureViews.length;e++){let n=t.colorTextureViews[e].getTexture()?.getFormat();n&&n!==r[e].format&&(console.log(`mismatched attachments for attachment ${e} on pipeline ${r[e].format} while encoder has ${n}`),console.trace())}if(!!t.depthTextureView!=`depthStencil`in n)console.log(`mismatched depth attachments`),console.trace();else if(t.depthTextureView){let e=t.depthTextureView.getTexture()?.getFormat();e&&e!==n.depthStencil.format&&(console.log(`mismatched depth attachments on pipeline ${n.depthStencil.format} while encoder has ${e}`),console.trace())}t.boundPipeline=e},e.replaceShaderCode=e=>{t.replaceShaderCodeFunction(e)},e.setColorTextureView=(e,n)=>{t.colorTextureViews[e]!==n&&(t.colorTextureViews[e]=n)},e.activateBindGroup=e=>{let n=t.boundPipeline.getDevice(),r=t.boundPipeline.getBindGroupLayoutIndex(e.getLabel());if(r<0){Me(`vtkWebGPURenderEncoder: could not find bind group layout ${e.getLabel()}`);return}t.handle.setBindGroup(r,e.getBindGroup(n));let i=n.getBindGroupLayoutDescription(e.getBindGroupLayout(n)),a=n.getBindGroupLayoutDescription(t.boundPipeline.getBindGroupLayout(r));i!==a&&(console.log(`renderEncoder ${t.pipelineHash} mismatched bind group layouts bind group has\n${i}\n versus pipeline\n${a}\n`),console.trace())},e.attachTextureViews=()=>{for(let e=0;e<t.colorTextureViews.length;e++)t.description.colorAttachments[e]?t.description.colorAttachments[e].view=t.colorTextureViews[e].getHandle():t.description.colorAttachments[e]={view:t.colorTextureViews[e].getHandle()};t.depthTextureView&&(t.description.depthStencilAttachment.view=t.depthTextureView.getHandle())},e.registerDrawCallback=(e,n)=>{for(let r=0;r<t.drawCallbacks.length;r++)if(t.drawCallbacks[r].pipeline===e){t.drawCallbacks[r].callbacks.push(n);return}t.drawCallbacks.push({pipeline:e,callbacks:[n]})};for(let n=0;n<U.length;n++)e[U[n]]=(...e)=>t.handle[U[n]](...e)}var Pe={description:null,handle:null,boundPipeline:null,pipelineHash:null,pipelineSettings:null,replaceShaderCodeFunction:null,depthTextureView:null,label:null};function Fe(t,n,r={}){Object.assign(n,Pe,r),g(t,n),n.description={colorAttachments:[{view:void 0,loadOp:`load`,storeOp:`store`}],depthStencilAttachment:{view:void 0,depthLoadOp:`clear`,depthClearValue:0,depthStoreOp:`store`}},n.replaceShaderCodeFunction=e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<f32>`,`outColor`);let n=t.getCode();n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`output.outColor = computedColor;`]).result,t.setCode(n)},n.pipelineSettings={primitive:{cullMode:`none`},depthStencil:{depthWriteEnabled:!0,depthCompare:`greater-equal`,format:`depth32float`},fragment:{targets:[{format:`rgba16float`,blend:{color:{srcFactor:`src-alpha`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}},n.colorTextureViews=[],ce(t,n,[`boundPipeline`,`colorTextureViews`]),e(t,n,[`depthTextureView`,`description`,`handle`,`label`,`pipelineHash`,`pipelineSettings`,`replaceShaderCodeFunction`]),Ne(t,n)}var W={newInstance:x(Fe,`vtkWebGPURenderEncoder`),extend:Fe};function Ie(e,t){t.classHierarchy.push(`vtkWebGPUOpaquePass`),e.traverse=(n,r)=>{if(t.deleted)return;t._currentParent=r;let i=r.getDevice();if(t.renderEncoder)t.colorTexture.resize(r.getCanvas().width,r.getCanvas().height),t.depthTexture.resize(r.getCanvas().width,r.getCanvas().height);else{e.createRenderEncoder(),t.colorTexture=M.newInstance({label:`opaquePassColor`}),t.colorTexture.create(i,{width:r.getCanvas().width,height:r.getCanvas().height,format:`rgba16float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_SRC});let n=t.colorTexture.createView(`opaquePassColorTexture`);t.renderEncoder.setColorTextureView(0,n),t.depthFormat=`depth32float`,t.depthTexture=M.newInstance({label:`opaquePassDepth`}),t.depthTexture.create(i,{width:r.getCanvas().width,height:r.getCanvas().height,format:t.depthFormat,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_SRC});let a=t.depthTexture.createView(`opaquePassDepthTexture`);t.renderEncoder.setDepthTextureView(a)}t.renderEncoder.attachTextureViews(),e.setCurrentOperation(`opaquePass`),n.setRenderEncoder(t.renderEncoder),n.traverse(e)},e.getColorTextureView=()=>t.renderEncoder.getColorTextureViews()[0],e.getDepthTextureView=()=>t.renderEncoder.getDepthTextureView(),e.createRenderEncoder=()=>{t.renderEncoder=W.newInstance({label:`OpaquePass`}),t.renderEncoder.setPipelineHash(`op`)},e.releaseGraphicsResources=()=>{t.renderEncoder=null,t.colorTexture=null,t.depthTexture=null}}var Le={renderEncoder:null,colorTexture:null,depthTexture:null};function Re(e,t,n={}){Object.assign(t,Le,n),O.extend(e,t,n),l.get(e,t,[`colorTexture`,`depthTexture`]),Ie(e,t)}var ze={newInstance:l.newInstance(Re,`vtkWebGPUOpaquePass`),extend:Re},Be=`
//VTK::Mapper::Dec

//VTK::TCoord::Dec

//VTK::RenderEncoder::Dec

//VTK::IOStructs::Dec

@fragment
fn main(
//VTK::IOStructs::Input
)
//VTK::IOStructs::Output
{
  var output: fragmentOutput;

  var tcoord: vec2<i32> = vec2<i32>(i32(input.fragPos.x), i32(input.fragPos.y));
  var reveal: f32 = textureLoad(oitpAccumTexture, tcoord, 0).r;
  if (reveal == 1.0) { discard; }
  var tcolor: vec4<f32> = textureLoad(oitpColorTexture, tcoord, 0);
  var total: f32 = max(tcolor.a, 0.01);
  var computedColor: vec4<f32> = vec4<f32>(tcolor.r/total, tcolor.g/total, tcolor.b/total, 1.0 - reveal);

  //VTK::RenderEncoder::Impl
  return output;
}
`;function Ve(e,t){t.classHierarchy.push(`vtkWebGPUOrderIndependentTranslucentPass`),e.traverse=(n,r)=>{if(t.deleted)return;t._currentParent=r;let i=r.getDevice();if(t.translucentRenderEncoder)t.translucentColorTexture.resizeToMatch(t.colorTextureView.getTexture()),t.translucentAccumulateTexture.resizeToMatch(t.colorTextureView.getTexture());else{e.createRenderEncoder(),e.createFinalEncoder(),t.translucentColorTexture=M.newInstance({label:`translucentPassColor`}),t.translucentColorTexture.create(i,{width:r.getCanvas().width,height:r.getCanvas().height,format:`rgba16float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING});let n=t.translucentColorTexture.createView(`oitpColorTexture`);t.translucentRenderEncoder.setColorTextureView(0,n),t.translucentAccumulateTexture=M.newInstance({label:`translucentPassAccumulate`}),t.translucentAccumulateTexture.create(i,{width:r.getCanvas().width,height:r.getCanvas().height,format:`r16float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING});let a=t.translucentAccumulateTexture.createView(`oitpAccumTexture`);t.translucentRenderEncoder.setColorTextureView(1,a),t.fullScreenQuad=d.newInstance(),t.fullScreenQuad.setDevice(r.getDevice()),t.fullScreenQuad.setPipelineHash(`oitpfsq`),t.fullScreenQuad.setTextureViews(t.translucentRenderEncoder.getColorTextureViews()),t.fullScreenQuad.setFragmentShaderTemplate(Be)}t.translucentRenderEncoder.setDepthTextureView(t.depthTextureView),t.translucentRenderEncoder.attachTextureViews(),e.setCurrentOperation(`translucentPass`),n.setRenderEncoder(t.translucentRenderEncoder),n.traverse(e),e.finalPass(r,n)},e.finalPass=(e,n)=>{t.translucentFinalEncoder.setColorTextureView(0,t.colorTextureView),t.translucentFinalEncoder.attachTextureViews(),t.translucentFinalEncoder.begin(e.getCommandEncoder()),n.scissorAndViewport(t.translucentFinalEncoder),t.fullScreenQuad.prepareAndDraw(t.translucentFinalEncoder),t.translucentFinalEncoder.end()},e.getTextures=()=>[t.translucentColorTexture,t.translucentAccumulateTexture],e.createRenderEncoder=()=>{t.translucentRenderEncoder=W.newInstance({label:`translucentRender`});let e=t.translucentRenderEncoder.getDescription();e.colorAttachments=[{view:void 0,clearValue:[0,0,0,0],loadOp:`clear`,storeOp:`store`},{view:void 0,clearValue:[1,0,0,0],loadOp:`clear`,storeOp:`store`}],e.depthStencilAttachment={view:void 0,depthLoadOp:`load`,depthStoreOp:`store`},t.translucentRenderEncoder.setReplaceShaderCodeFunction(e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<f32>`,`outColor`),t.addOutput(`f32`,`outAccum`),t.addBuiltinInput(`vec4<f32>`,`@builtin(position) fragPos`);let n=t.getCode();n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`var w: f32 = computedColor.a * pow(0.1 + input.fragPos.z, 2.0);`,`output.outColor = vec4<f32>(computedColor.rgb*w, w);`,`output.outAccum = computedColor.a;`]).result,t.setCode(n)}),t.translucentRenderEncoder.setPipelineHash(`oitpr`),t.translucentRenderEncoder.setPipelineSettings({primitive:{cullMode:`none`},depthStencil:{depthWriteEnabled:!1,depthCompare:`greater`,format:`depth32float`},fragment:{targets:[{format:`rgba16float`,blend:{color:{srcFactor:`one`,dstFactor:`one`},alpha:{srcFactor:`one`,dstFactor:`one`}}},{format:`r16float`,blend:{color:{srcFactor:`zero`,dstFactor:`one-minus-src`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}})},e.createFinalEncoder=()=>{t.translucentFinalEncoder=W.newInstance({label:`translucentFinal`}),t.translucentFinalEncoder.setDescription({colorAttachments:[{view:null,loadOp:`load`,storeOp:`store`}]}),t.translucentFinalEncoder.setReplaceShaderCodeFunction(e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<f32>`,`outColor`),t.addBuiltinInput(`vec4<f32>`,`@builtin(position) fragPos`);let n=t.getCode();n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`output.outColor = vec4<f32>(computedColor.rgb, computedColor.a);`]).result,t.setCode(n)}),t.translucentFinalEncoder.setPipelineHash(`oitpf`),t.translucentFinalEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:`rgba16float`,blend:{color:{srcFactor:`src-alpha`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}})},e.releaseGraphicsResources=()=>{t.translucentRenderEncoder=null,t.translucentFinalEncoder=null,t.translucentColorTexture=null,t.translucentAccumulateTexture=null,t.fullScreenQuad=null}}var He={colorTextureView:null,depthTextureView:null};function Ue(e,t,n={}){Object.assign(t,He,n),O.extend(e,t,n),l.setGet(e,t,[`colorTextureView`,`depthTextureView`]),Ve(e,t)}var We={newInstance:l.newInstance(Ue,`vtkWebGPUOrderIndependentTranslucentPass`),extend:Ue},Ge=`
//VTK::Renderer::Dec

//VTK::Mapper::Dec

//VTK::TCoord::Dec

//VTK::Volume::TraverseDec

//VTK::RenderEncoder::Dec

//VTK::IOStructs::Dec

fn getTextureValue(vTex: texture_3d<f32>, tpos: vec4<f32>) -> f32
{
  // todo multicomponent support
  return textureSampleLevel(vTex, clampSampler, tpos.xyz, 0.0).r;
}

fn intersectRayBoundsWithClipPlanes(vNum: i32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>, rayBounds: vec2<f32>) -> vec2<f32>
{
  var result: vec2<f32> = rayBounds;
  let clipCount: i32 = i32(volumeSSBO.values[vNum].clipPlaneStates.x);
  if (clipCount <= 0)
  {
    return result;
  }

  ${Array.from({length:6},(e,t)=>`
  if (clipCount > ${t})
  {
    let clipPlane${t}: vec4<f32> = volumeSSBO.values[vNum].clipPlane${t};
    let rayDirRatio${t}: f32 = dot(rayStepSC, clipPlane${t});
    let equationResult${t}: f32 = dot(minPosSC, clipPlane${t});

    let absRayDirRatio${t}: f32 = abs(rayDirRatio${t});
    if (absRayDirRatio${t} > 1e-6)
    {
      let intersection${t}: f32 = -equationResult${t} / rayDirRatio${t};
      result.x = select(result.x, max(result.x, intersection${t}), rayDirRatio${t} > 0.0);
      result.y = select(result.y, min(result.y, intersection${t}), rayDirRatio${t} < 0.0);
    }
    else if (equationResult${t} < 0.0)
    {
      result.x = result.y;
    }

    if (result.x >= result.y)
    {
      return result;
    }
  }`).join(`
`)}

  return result;
}

fn getGradient(vTex: texture_3d<f32>, tpos: vec4<f32>, vNum: i32, scalar: f32) -> vec4<f32>
{
  var result: vec4<f32>;

  var tstep: vec4<f32> = volumeSSBO.values[vNum].tstep;
  result.x = getTextureValue(vTex, tpos + vec4<f32>(tstep.x, 0.0, 0.0, 1.0)) - scalar;
  result.y = getTextureValue(vTex, tpos + vec4<f32>(0.0, tstep.y, 0.0, 1.0)) - scalar;
  result.z = getTextureValue(vTex, tpos + vec4<f32>(0.0, 0.0, tstep.z, 1.0)) - scalar;
  result.w = 0.0;

  // divide by spacing as that is our delta
  result = result / volumeSSBO.values[vNum].spacing;
  // now we have a gradient in unit tcoords

  var grad: f32 = length(result.xyz);
  if (grad > 0.0)
  {
    // rotate to View Coords, needed for lighting and shading
    var nMat: mat4x4<f32> = rendererUBO.SCVCMatrix * volumeSSBO.values[vNum].planeNormals;
    result = nMat * result;
    result = result / length(result);
  }

  // store gradient magnitude in .w
  result.w = grad;

  return result;
}

fn processVolume(vTex: texture_3d<f32>, vNum: i32, cNum: i32, posSC: vec4<f32>, tfunRows: f32) -> vec4<f32>
{
  var outColor: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 0.0);

  // convert to tcoords and reject if outside the volume
  var tpos: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*posSC;
  if (tpos.x < 0.0 || tpos.y < 0.0 || tpos.z < 0.0 ||
      tpos.x > 1.0 || tpos.y > 1.0 || tpos.z > 1.0) { return outColor; }

  var scalar: f32 = getTextureValue(vTex, tpos);

  var coord: vec2<f32> =
    vec2<f32>(scalar * componentSSBO.values[cNum].cScale + componentSSBO.values[cNum].cShift,
      (0.5 + 2.0 * f32(vNum)) / tfunRows);
  var color: vec4<f32> = textureSampleLevel(tfunTexture, clampSampler, coord, 0.0);

  var gofactor: f32 = 1.0;
  var normal: vec4<f32> = vec4<f32>(0.0,0.0,0.0,0.0);
  if (componentSSBO.values[cNum].gomin <  1.0 || volumeSSBO.values[vNum].shade[0] > 0.0)
  {
    normal = getGradient(vTex, tpos, vNum, scalar);
    if (componentSSBO.values[cNum].gomin <  1.0)
    {
      gofactor = clamp(normal.a*componentSSBO.values[cNum].goScale + componentSSBO.values[cNum].goShift,
      componentSSBO.values[cNum].gomin, componentSSBO.values[cNum].gomax);
    }
  }

  coord.x = (scalar * componentSSBO.values[cNum].oScale + componentSSBO.values[cNum].oShift);
  var opacity: f32 = textureSampleLevel(ofunTexture, clampSampler, coord, 0.0).r;

  if (volumeSSBO.values[vNum].shade[0] > 0.0)
  {
    color = color*abs(normal.z);
  }

  outColor = vec4<f32>(color.rgb, gofactor * opacity);

  return outColor;
}

// adjust the start and end point of a raycast such that it intersects the unit cube.
// This function is used to take a raycast starting point and step vector
// and numSteps and return the startijng and ending steps for intersecting the
// unit cube. Recall for a 3D texture, the unit cube is the range of texture coordsinates
// that have valid values. So this funtion can be used to take a ray in texture coordinates
// and bound it to intersecting the texture.
//
fn adjustBounds(tpos: vec4<f32>, tstep: vec4<f32>, numSteps: f32) -> vec2<f32>
{
  var result: vec2<f32> = vec2<f32>(0.0, numSteps);
  var tpos2: vec4<f32> = tpos + tstep*numSteps;

  // move tpos to the start of the volume
  var adjust: f32 =
    min(
      max(tpos.x/tstep.x, (tpos.x - 1.0)/tstep.x),
      min(
        max((tpos.y - 1.0)/tstep.y, tpos.y/tstep.y),
        max((tpos.z - 1.0)/tstep.z, tpos.z/tstep.z)));
  if (adjust < 0.0)
  {
    result.x = result.x - adjust;
  }

  // adjust length to the end
  adjust =
    max(
      min(tpos2.x/tstep.x, (tpos2.x - 1.0)/tstep.x),
      max(
        min((tpos2.y - 1.0)/tstep.y, tpos2.y/tstep.y),
        min((tpos2.z - 1.0)/tstep.z, tpos2.z/tstep.z)));
  if (adjust > 0.0)
  {
    result.y = result.y - adjust;
  }

  return result;
}

fn getSimpleColor(scalar: f32, vNum: i32, cNum: i32) -> vec4<f32>
{
  // how many rows (tfuns) do we have in our tfunTexture
  var tfunRows: f32 = f32(textureDimensions(tfunTexture).y);

  var coord: vec2<f32> =
    vec2<f32>(scalar * componentSSBO.values[cNum].cScale + componentSSBO.values[cNum].cShift,
      (0.5 + 2.0 * f32(vNum)) / tfunRows);
  var color: vec4<f32> = textureSampleLevel(tfunTexture, clampSampler, coord, 0.0);
  coord.x = (scalar * componentSSBO.values[cNum].oScale + componentSSBO.values[cNum].oShift);
  var opacity: f32 = textureSampleLevel(ofunTexture, clampSampler, coord, 0.0).r;
  return vec4<f32>(color.rgb, opacity);
}

fn traverseMax(vTex: texture_3d<f32>, vNum: i32, cNum: i32, rayLengthSC: f32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>)
{
  // convert to tcoords and reject if outside the volume
  var numSteps: f32 = rayLengthSC/mapperUBO.SampleDistance;
  var tpos: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*minPosSC;
  var tpos2: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*(minPosSC + rayStepSC);
  var tstep: vec4<f32> = tpos2 - tpos;

  var rayBounds: vec2<f32> = intersectRayBoundsWithClipPlanes(
    vNum,
    minPosSC,
    rayStepSC,
    adjustBounds(tpos, tstep, numSteps));

  // did we hit anything
  if (rayBounds.x >= rayBounds.y)
  {
    traverseVals[vNum] = vec4<f32>(0.0,0.0,0.0,0.0);
    return;
  }

  tpos = tpos + tstep*rayBounds.x;
  var curDist: f32 = rayBounds.x;
  var maxVal: f32 = -1.0e37;
  loop
  {
    var scalar: f32 = getTextureValue(vTex, tpos);
    if (scalar > maxVal)
    {
      maxVal = scalar;
    }

    // increment position
    curDist = curDist + 1.0;
    tpos = tpos + tstep;

    // check if we have reached a terminating condition
    if (curDist > rayBounds.y) { break; }
  }

  // process to get the color and opacity
  traverseVals[vNum] = getSimpleColor(maxVal, vNum, cNum);
}

fn traverseMin(vTex: texture_3d<f32>, vNum: i32, cNum: i32, rayLengthSC: f32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>)
{
  // convert to tcoords and reject if outside the volume
  var numSteps: f32 = rayLengthSC/mapperUBO.SampleDistance;
  var tpos: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*minPosSC;
  var tpos2: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*(minPosSC + rayStepSC);
  var tstep: vec4<f32> = tpos2 - tpos;

  var rayBounds: vec2<f32> = intersectRayBoundsWithClipPlanes(
    vNum,
    minPosSC,
    rayStepSC,
    adjustBounds(tpos, tstep, numSteps));

  // did we hit anything
  if (rayBounds.x >= rayBounds.y)
  {
    traverseVals[vNum] = vec4<f32>(0.0,0.0,0.0,0.0);
    return;
  }

  tpos = tpos + tstep*rayBounds.x;
  var curDist: f32 = rayBounds.x;
  var minVal: f32 = 1.0e37;
  loop
  {
    var scalar: f32 = getTextureValue(vTex, tpos);
    if (scalar < minVal)
    {
      minVal = scalar;
    }

    // increment position
    curDist = curDist + 1.0;
    tpos = tpos + tstep;

    // check if we have reached a terminating condition
    if (curDist > rayBounds.y) { break; }
  }

  // process to get the color and opacity
  traverseVals[vNum] = getSimpleColor(minVal, vNum, cNum);
}

fn traverseAverage(vTex: texture_3d<f32>, vNum: i32, cNum: i32, rayLengthSC: f32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>)
{
  // convert to tcoords and reject if outside the volume
  var numSteps: f32 = rayLengthSC/mapperUBO.SampleDistance;
  var tpos: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*minPosSC;
  var tpos2: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*(minPosSC + rayStepSC);
  var tstep: vec4<f32> = tpos2 - tpos;

  var rayBounds: vec2<f32> = intersectRayBoundsWithClipPlanes(
    vNum,
    minPosSC,
    rayStepSC,
    adjustBounds(tpos, tstep, numSteps));

  // did we hit anything
  if (rayBounds.x >= rayBounds.y)
  {
    traverseVals[vNum] = vec4<f32>(0.0,0.0,0.0,0.0);
    return;
  }

  let ipRange: vec4<f32> = volumeSSBO.values[vNum].ipScalarRange;
  tpos = tpos + tstep*rayBounds.x;
  var curDist: f32 = rayBounds.x;
  var avgVal: f32 = 0.0;
  var sampleCount: f32 = 0.0;
  loop
  {
    var sample: f32 = getTextureValue(vTex, tpos);
    // right now leave filtering off until WebGL changes get merged
    // if (ipRange.z == 0.0 || sample >= ipRange.x && sample <= ipRange.y)
    // {
      avgVal = avgVal + sample;
      sampleCount = sampleCount + 1.0;
    // }

    // increment position
    curDist = curDist + 1.0;
    tpos = tpos + tstep;

    // check if we have reached a terminating condition
    if (curDist > rayBounds.y) { break; }
  }

  if (sampleCount <= 0.0)
  {
    traverseVals[vNum] = vec4<f32>(0.0,0.0,0.0,0.0);
    return;
  }

  // process to get the color and opacity
  traverseVals[vNum] = getSimpleColor(avgVal/sampleCount, vNum, cNum);
}

fn traverseAdditive(vTex: texture_3d<f32>, vNum: i32, cNum: i32, rayLengthSC: f32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>)
{
  // convert to tcoords and reject if outside the volume
  var numSteps: f32 = rayLengthSC/mapperUBO.SampleDistance;
  var tpos: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*minPosSC;
  var tpos2: vec4<f32> = volumeSSBO.values[vNum].SCTCMatrix*(minPosSC + rayStepSC);
  var tstep: vec4<f32> = tpos2 - tpos;

  var rayBounds: vec2<f32> = intersectRayBoundsWithClipPlanes(
    vNum,
    minPosSC,
    rayStepSC,
    adjustBounds(tpos, tstep, numSteps));

  // did we hit anything
  if (rayBounds.x >= rayBounds.y)
  {
    traverseVals[vNum] = vec4<f32>(0.0,0.0,0.0,0.0);
    return;
  }

  let ipRange: vec4<f32> = volumeSSBO.values[vNum].ipScalarRange;
  tpos = tpos + tstep*rayBounds.x;
  var curDist: f32 = rayBounds.x;
  var sumVal: f32 = 0.0;
  loop
  {
    var sample: f32 = getTextureValue(vTex, tpos);
    // right now leave filtering off until WebGL changes get merged
    // if (ipRange.z == 0.0 || sample >= ipRange.x && sample <= ipRange.y)
    // {
      sumVal = sumVal + sample;
    // }
    // increment position
    curDist = curDist + 1.0;
    tpos = tpos + tstep;

    // check if we have reached a terminating condition
    if (curDist > rayBounds.y) { break; }
  }

  // process to get the color and opacity
  traverseVals[vNum] = getSimpleColor(sumVal, vNum, cNum);
}

fn composite(rayLengthSC: f32, minPosSC: vec4<f32>, rayStepSC: vec4<f32>) -> vec4<f32>
{
  // initial ray position is at the beginning
  var rayPosSC: vec4<f32> = minPosSC;

  // how many rows (tfuns) do we have in our tfunTexture
  var tfunRows: f32 = f32(textureDimensions(tfunTexture).y);

  var curDist: f32 = 0.0;
  var computedColor: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  var sampleColor: vec4<f32>;
  var numSteps: f32 = rayLengthSC/mapperUBO.SampleDistance;
//VTK::Volume::TraverseCalls
//VTK::Volume::TraverseInit

  loop
  {
    // for each volume, sample and accumulate color
//VTK::Volume::CompositeCalls

    // increment position
    curDist = curDist + mapperUBO.SampleDistance;
    rayPosSC = rayPosSC + rayStepSC;

    // check if we have reached a terminating condition
    if (curDist > rayLengthSC) { break; }
    if (computedColor.a > 0.98) { break; }
  }
  return computedColor;
}

@fragment
fn main(
//VTK::IOStructs::Input
)
//VTK::IOStructs::Output
{
  var output: fragmentOutput;

  var rayMax: f32 = textureSampleLevel(maxTexture, clampSampler, input.tcoordVS, 0.0).r;
  var rayMin: f32 = textureSampleLevel(minTexture, clampSampler, input.tcoordVS, 0.0).r;

  // discard empty rays
  if (rayMax <= rayMin) { discard; }
  else
  {
    // compute start and end ray positions in view coordinates
    var minPosSC: vec4<f32> = rendererUBO.PCSCMatrix*vec4<f32>(2.0 * input.tcoordVS.x - 1.0, 1.0 - 2.0 * input.tcoordVS.y, rayMax, 1.0);
    minPosSC = minPosSC * (1.0 / minPosSC.w);
    var maxPosSC: vec4<f32> = rendererUBO.PCSCMatrix*vec4<f32>(2.0 * input.tcoordVS.x - 1.0, 1.0 - 2.0 * input.tcoordVS.y, rayMin, 1.0);
    maxPosSC = maxPosSC * (1.0 / maxPosSC.w);

    var rayLengthSC: f32 = distance(minPosSC.xyz, maxPosSC.xyz);
    var rayStepSC: vec4<f32> = (maxPosSC - minPosSC)*(mapperUBO.SampleDistance/rayLengthSC);
    rayStepSC.w = 0.0;

    var computedColor: vec4<f32>;

//VTK::Volume::Loop

//VTK::RenderEncoder::Impl
  }

  return output;
}
`,G=new Float64Array(16),K=new Float64Array(16);function Ke(e,t){t.classHierarchy.push(`vtkWebGPUVolumePassFSQ`),e.replaceShaderPosition=(e,t,n)=>{let r=t.getShaderDescription(`vertex`);r.addBuiltinOutput(`vec4<f32>`,`@builtin(position) Position`);let a=r.getCode();a=i.substitute(a,`//VTK::Position::Impl`,[`output.tcoordVS = vec2<f32>(vertexBC.x * 0.5 + 0.5, 1.0 - vertexBC.y * 0.5 - 0.5);`,`output.Position = vec4<f32>(vertexBC, 1.0);`]).result,r.setCode(a),t.getShaderDescription(`fragment`).addBuiltinInput(`vec4<f32>`,`@builtin(position) fragPos`)},t.shaderReplacements.set(`replaceShaderPosition`,e.replaceShaderPosition),e.replaceShaderVolume=(e,n,r)=>{let a=n.getShaderDescription(`fragment`),o=a.getCode(),s=[],c=[],l=[];for(let e=0;e<t.volumes.length;e++)t.volumes[e].getRenderable().getMapper().getBlendMode()===j.COMPOSITE_BLEND?(c.push(`  var tpos${e}: vec4<f32> = volumeSSBO.values[${e}].SCTCMatrix*minPosSC;`),c.push(`  var tpos2_${e}: vec4<f32> = volumeSSBO.values[${e}].SCTCMatrix*(minPosSC + rayStepSC);`),c.push(`  var tstep${e}: vec4<f32> = tpos2_${e} - tpos${e};`),c.push(`  var rayBounds${e}: vec2<f32> = intersectRayBoundsWithClipPlanes(${e}, minPosSC, rayStepSC, adjustBounds(tpos${e}, tstep${e}, numSteps));`),s.push(`    if (curDist >= rayBounds${e}.x * mapperUBO.SampleDistance && curDist <= rayBounds${e}.y * mapperUBO.SampleDistance) {`),s.push(`      sampleColor = processVolume(volTexture${e}, ${e}, ${t.rowStarts[e]}, rayPosSC, tfunRows);`),s.push(`    computedColor = vec4<f32>(
          sampleColor.a * sampleColor.rgb * (1.0 - computedColor.a) + computedColor.rgb,
          (1.0 - computedColor.a)*sampleColor.a + computedColor.a);`),s.push(`    }`)):(l.push(`  sampleColor = traverseVals[${e}];`),l.push(`  computedColor = vec4<f32>(
          sampleColor.a * sampleColor.rgb * (1.0 - computedColor.a) + computedColor.rgb,
          (1.0 - computedColor.a)*sampleColor.a + computedColor.a);`));o=i.substitute(o,`//VTK::Volume::CompositeCalls`,s).result,o=i.substitute(o,`//VTK::Volume::TraverseCalls`,l).result,o=i.substitute(o,`//VTK::Volume::TraverseInit`,c).result,o=i.substitute(o,`//VTK::Volume::TraverseDec`,[`var<private> traverseVals: array<vec4<f32>,${t.volumes.length}>;`]).result;let u=!1;for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable().getMapper().getBlendMode();n===j.COMPOSITE_BLEND?u=!0:n===j.MAXIMUM_INTENSITY_BLEND?o=i.substitute(o,`//VTK::Volume::Loop`,[`    traverseMax(volTexture${e}, ${e}, ${e}, rayLengthSC, minPosSC, rayStepSC);`,`    computedColor = traverseVals[${e}];`,`//VTK::Volume::Loop`]).result:n===j.MINIMUM_INTENSITY_BLEND?o=i.substitute(o,`//VTK::Volume::Loop`,[`    traverseMin(volTexture${e}, ${e}, ${e}, rayLengthSC, minPosSC, rayStepSC);`,`    computedColor = traverseVals[${e}];`,`//VTK::Volume::Loop`]).result:n===j.AVERAGE_INTENSITY_BLEND?o=i.substitute(o,`//VTK::Volume::Loop`,[`    traverseAverage(volTexture${e}, ${e}, ${e}, rayLengthSC, minPosSC, rayStepSC);`,`    computedColor = traverseVals[${e}];`,`//VTK::Volume::Loop`]).result:n===j.ADDITIVE_INTENSITY_BLEND&&(o=i.substitute(o,`//VTK::Volume::Loop`,[`    traverseAdditive(volTexture${e}, ${e}, ${e}, rayLengthSC, minPosSC, rayStepSC);`,`    computedColor = traverseVals[${e}];`,`//VTK::Volume::Loop`]).result)}u&&(o=i.substitute(o,`//VTK::Volume::Loop`,[`    computedColor = composite(rayLengthSC, minPosSC, rayStepSC);`]).result),a.setCode(o)},t.shaderReplacements.set(`replaceShaderVolume`,e.replaceShaderVolume),e.updateLUTImage=n=>{let r=e.getMTime();for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable(),i=n.getMapper().getInputData();r=Math.max(r,n.getMTime(),i.getMTime())}if(r<t.lutBuildTime.getMTime())return;t.numRows=0,t.rowStarts=[];for(let e=0;e<t.volumes.length;e++){t.rowStarts.push(t.numRows);let n=t.volumes[e].getRenderable(),r=n.getMapper(),i=n.getProperty(),a=r.getInputData(),o=(a.getPointData()&&a.getPointData().getScalars()).getNumberOfComponents(),s=i.getIndependentComponents()?o:1;t.numRows+=s}let i=new Uint8ClampedArray(t.numRows*2*t.rowLength*4),a=new Float32Array(t.numRows*2*t.rowLength),o=0,s=new Float32Array(t.rowLength*3),c=t.rowLength;for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable(),r=n.getMapper(),l=n.getProperty(),u=r.getInputData(),d=(u.getPointData()&&u.getPointData().getScalars()).getNumberOfComponents(),f=l.getIndependentComponents()?d:1;for(let e=0;e<f;++e){let n=l.getRGBTransferFunction(e),r=n.getRange();n.getTable(r[0],r[1],c,s,1);let u=o*c*4;for(let e=0;e<c;++e){i[u+e*4]=255*s[e*3],i[u+e*4+1]=255*s[e*3+1],i[u+e*4+2]=255*s[e*3+2],i[u+e*4+3]=255;for(let t=0;t<4;t++)i[u+(c+e)*4+t]=i[u+e*4+t]}let d=l.getScalarOpacity(e),f=t.sampleDist/l.getScalarOpacityUnitDistance(e),p=d.getRange();d.getTable(p[0],p[1],c,s,1),u=o*c;for(let e=0;e<c;++e)a[u+e]=1-(1-s[e])**f,a[u+e+c]=a[u+e];o+=2}}{let e={nativeArray:i,width:t.rowLength,height:t.numRows*2,depth:1,format:`rgba8unorm`},r=n.getTextureManager().getTexture(e).createView(`tfunTexture`);t.textureViews[2]=r}{let e={nativeArray:a,width:t.rowLength,height:t.numRows*2,depth:1,format:`r16float`},r=n.getTextureManager().getTexture(e).createView(`ofunTexture`);t.textureViews[3]=r}t.lutBuildTime.modified()},e.updateSSBO=n=>{let i=Math.max(e.getMTime(),t.WebGPURenderer.getStabilizedTime());for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable(),r=n.getMapper(),a=r.getInputData();i=Math.max(i,n.getMTime(),a.getMTime(),r.getMTime(),r.getClippingPlanesMTime())}if(i<t.SSBO.getSendTime())return;let o=t.WebGPURenderer.getStabilizedCenterByReference();t.SSBO.clearData(),t.SSBO.setNumberOfInstances(t.volumes.length);let l=new Float64Array(t.volumes.length*16),u=new Float64Array(t.volumes.length*16),d=Array.from({length:6},()=>new Float64Array(t.volumes.length*4)),f=new Float64Array(t.volumes.length*4),p=new Float64Array(t.volumes.length*4),m=new Float64Array(t.volumes.length*4),g=new Float64Array(t.volumes.length*4),_=new Float64Array(t.volumes.length*4);for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable(),i=n.getMapper(),h=i.getInputData();v(G),te(G,G,o);let y=n.getMatrix();ee(K,y),me(K,K),a(G,K,G);let b=h.getWorldToIndex();a(G,b,G);let x=h.getDimensions();v(K),c(K,K,[1/x[0],1/x[1],1/x[2]]),a(G,K,G);for(let t=0;t<16;t++)l[e*16+t]=G[t];me(G,G);for(let t=0;t<4;t++)u[e*16+t*4]=G[t*4],u[e*16+t*4+1]=G[t*4+1],u[e*16+t*4+2]=G[t*4+2],u[e*16+t*4+3]=0;p[e*4]=1/x[0],p[e*4+1]=1/x[1],p[e*4+2]=1/x[2],p[e*4+3]=1,m[e*4]=+!!n.getProperty().getShade();let S=h.getSpacing();g[e*4]=S[0],g[e*4+1]=S[1],g[e*4+2]=S[2],g[e*4+3]=1;let C=t.textureViews[e+4].getTexture().getScale(),w=n.getProperty().getIpScalarRange();_[e*4]=w[0]/C,_[e*4+1]=w[1]/C,_[e*4+2]=n.getProperty().getFilterMode(),s(K,[-o[0],-o[1],-o[2]]);let T=r(i,K,t.clipPlanes);f[e*4]=T;for(let n=0;n<T;n++){let r=e*4;d[n][r]=t.clipPlanes[n][0],d[n][r+1]=t.clipPlanes[n][1],d[n][r+2]=t.clipPlanes[n][2],d[n][r+3]=t.clipPlanes[n][3]}}t.SSBO.addEntry(`SCTCMatrix`,`mat4x4<f32>`),t.SSBO.addEntry(`planeNormals`,`mat4x4<f32>`),t.SSBO.addEntry(`shade`,`vec4<f32>`),t.SSBO.addEntry(`tstep`,`vec4<f32>`),t.SSBO.addEntry(`spacing`,`vec4<f32>`),t.SSBO.addEntry(`ipScalarRange`,`vec4<f32>`),de(t.SSBO,`clipPlane`),t.SSBO.addEntry(`clipPlaneStates`,`vec4<f32>`),t.SSBO.setAllInstancesFromArray(`SCTCMatrix`,l),t.SSBO.setAllInstancesFromArray(`planeNormals`,u),t.SSBO.setAllInstancesFromArray(`shade`,m),t.SSBO.setAllInstancesFromArray(`tstep`,p),t.SSBO.setAllInstancesFromArray(`spacing`,g),t.SSBO.setAllInstancesFromArray(`ipScalarRange`,_);for(let e=0;e<6;e++)t.SSBO.setAllInstancesFromArray(`clipPlane${e}`,d[e]);t.SSBO.setAllInstancesFromArray(`clipPlaneStates`,f),t.SSBO.send(n),t.componentSSBO.clearData(),t.componentSSBO.setNumberOfInstances(t.numRows);let y=new Float64Array(t.numRows),b=new Float64Array(t.numRows),x=new Float64Array(t.numRows),S=new Float64Array(t.numRows),C=new Float64Array(t.numRows),w=new Float64Array(t.numRows),T=new Float64Array(t.numRows),E=new Float64Array(t.numRows),D=0;for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable(),r=n.getMapper(),i=n.getProperty(),a=r.getInputData(),o=(a.getPointData()&&a.getPointData().getScalars()).getNumberOfComponents(),s=i.getIndependentComponents(),c=t.textureViews[e+4].getTexture().getFormat(),l=h.getDetailsFromTextureFormat(c),u=l.elementSize===2&&l.sampleType===`float`,d={scale:[255],offset:[0]};u&&(d.scale[0]=1);for(let e=0;e<o;e++){let t=s?e:0,n=d.scale[e],r=i.getScalarOpacity(t).getRange(),a=n/(r[1]-r[0]);S[D]=(d.offset[e]-r[0])/(r[1]-r[0]),x[D]=a;let o=i.getRGBTransferFunction(t).getRange();if(b[D]=(d.offset[e]-o[0])/(o[1]-o[0]),y[D]=n/(o[1]-o[0]),i.getUseGradientOpacity(t)){let e=i.getGradientOpacityMinimumOpacity(t),r=i.getGradientOpacityMaximumOpacity(t);C[D]=e,w[D]=r;let a=[i.getGradientOpacityMinimumValue(t),i.getGradientOpacityMaximumValue(t)];E[D]=n*(r-e)/(a[1]-a[0]),T[D]=-a[0]*(r-e)/(a[1]-a[0])+e}else C[D]=1,w[D]=1,E[D]=0,T[D]=1;D++}}t.componentSSBO.addEntry(`cScale`,`f32`),t.componentSSBO.addEntry(`cShift`,`f32`),t.componentSSBO.addEntry(`oScale`,`f32`),t.componentSSBO.addEntry(`oShift`,`f32`),t.componentSSBO.addEntry(`goShift`,`f32`),t.componentSSBO.addEntry(`goScale`,`f32`),t.componentSSBO.addEntry(`gomin`,`f32`),t.componentSSBO.addEntry(`gomax`,`f32`),t.componentSSBO.setAllInstancesFromArray(`cScale`,y),t.componentSSBO.setAllInstancesFromArray(`cShift`,b),t.componentSSBO.setAllInstancesFromArray(`oScale`,x),t.componentSSBO.setAllInstancesFromArray(`oShift`,S),t.componentSSBO.setAllInstancesFromArray(`goScale`,E),t.componentSSBO.setAllInstancesFromArray(`goShift`,T),t.componentSSBO.setAllInstancesFromArray(`gomin`,C),t.componentSSBO.setAllInstancesFromArray(`gomax`,w),t.componentSSBO.send(n)};let n=e.updateBuffers;e.updateBuffers=()=>{n();let r=t.volumes[0].getRenderable().getMapper().getSampleDistance();for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable().getMapper().getSampleDistance();n<r&&(r=n)}t.sampleDist!==r&&(t.sampleDist=r,t.UBO.setValue(`SampleDistance`,r),t.UBO.sendIfNeeded(t.device));for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable().getMapper().getInputData(),r=t.device.getTextureManager().getTextureForImageData(n);if(!t.textureViews[e+4]||t.textureViews[e+4].getTexture()!==r){let n=r.createView(`volTexture${e}`);t.textureViews[e+4]=n}}if(t.volumes.length<t.lastVolumeLength)for(let e=t.volumes.length;e<t.lastVolumeLength;e++)t.textureViews.pop();t.lastVolumeLength=t.volumes.length,e.updateLUTImage(t.device),e.updateSSBO(t.device),t.clampSampler||(t.clampSampler=y.newInstance({label:`clampSampler`}),t.clampSampler.create(t.device,{minFilter:`linear`,magFilter:`linear`}))},e.computePipelineHash=()=>{t.pipelineHash=`volfsq`;for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable().getMapper().getBlendMode();t.pipelineHash+=`${n}`}},e.setVolumes=n=>{if(!t.volumes||t.volumes.length!==n.length)t.volumes=[...n],e.modified();else for(let r=0;r<n.length;r++)if(n[r]!==t.volumes[r]){t.volumes=[...n],e.modified();return}};let o=e.getBindables;e.getBindables=()=>{let e=o();return e.push(t.componentSSBO),e.push(t.clampSampler),e}}var qe={volumes:null,rowLength:1024,lastVolumeLength:0};function Je(e,r,i={}){Object.assign(r,qe,i),d.extend(e,r,i),r.fragmentShaderTemplate=Ge,r.UBO=n.newInstance({label:`mapperUBO`}),r.UBO.addEntry(`SampleDistance`,`f32`),r.SSBO=t.newInstance({label:`volumeSSBO`}),r.componentSSBO=t.newInstance({label:`componentSSBO`}),r.lutBuildTime={},l.obj(r.lutBuildTime,{mtime:0}),r.clipPlanes=Array.from({length:6},()=>[0,0,0,0]),Ke(e,r)}var Ye={newInstance:l.newInstance(Je,`vtkWebGPUVolumePassFSQ`),extend:Je},{Representation:Xe}=S,{BufferUsage:q,PrimitiveTypes:Ze}=m,J=[[0,4,6],[0,6,2],[1,3,7],[1,7,5],[0,5,4],[0,1,5],[2,6,7],[2,7,3],[0,3,1],[0,2,3],[4,5,7],[4,7,6]],Qe=`
//VTK::Renderer::Dec

//VTK::Select::Dec

//VTK::VolumePass::Dec

//VTK::TCoord::Dec

//VTK::RenderEncoder::Dec

//VTK::Mapper::Dec

//VTK::IOStructs::Dec

@fragment
fn main(
//VTK::IOStructs::Input
)
//VTK::IOStructs::Output
{
  var output : fragmentOutput;

  //VTK::Select::Impl

  //VTK::TCoord::Impl

  //VTK::VolumePass::Impl

  // use the maximum (closest) of the current value and the zbuffer
  // the blend func will then take the min to find the farthest stop value
  var stopval: f32 = max(input.fragPos.z, textureLoad(opaquePassDepthTexture, vec2<i32>(i32(input.fragPos.x), i32(input.fragPos.y)), 0));

  //VTK::RenderEncoder::Impl
  return output;
}
`,$e=`
//VTK::Renderer::Dec

//VTK::Mapper::Dec

//VTK::TCoord::Dec

//VTK::RenderEncoder::Dec

//VTK::IOStructs::Dec

@fragment
fn main(
//VTK::IOStructs::Input
)
//VTK::IOStructs::Output
{
  var output: fragmentOutput;

  var computedColor: vec4<f32> = textureSample(volumePassColorTexture,
    volumePassColorTextureSampler, mapperUBO.tscale*input.tcoordVS);

  //VTK::RenderEncoder::Impl
  return output;
}
`;function et(e,t){t.classHierarchy.push(`vtkWebGPUVolumePass`),e.initialize=r=>{t._clearEncoder||e.createClearEncoder(r),t._mergeEncoder||e.createMergeEncoder(r),t._copyEncoder||e.createCopyEncoder(r),t._depthRangeEncoder||e.createDepthRangeEncoder(r),t.fullScreenQuad||(t.fullScreenQuad=Ye.newInstance(),t.fullScreenQuad.setDevice(r.getDevice()),t.fullScreenQuad.setTextureViews([...t._depthRangeEncoder.getColorTextureViews()])),t._volumeCopyQuad||(t._volumeCopyQuad=d.newInstance(),t._volumeCopyQuad.setPipelineHash(`volpassfsq`),t._volumeCopyQuad.setDevice(r.getDevice()),t._volumeCopyQuad.setFragmentShaderTemplate($e),t._copyUBO=n.newInstance({label:`mapperUBO`}),t._copyUBO.addEntry(`tscale`,`vec2<f32>`),t._volumeCopyQuad.setUBO(t._copyUBO),t._volumeCopyQuad.setTextureViews([t._colorTextureView]))},e.traverse=(n,r)=>{if(t.deleted)return;t._currentParent=r,e.initialize(r),e.computeTiming(r),e.renderDepthBounds(n,r),t._firstGroup=!0;let i=r.getDevice(),a=i.getHandle().limits.maxSampledTexturesPerShaderStage-4;if(t.volumes.length>a){let i=n.getRenderable().getActiveCamera().getPosition(),o=[];for(let e=0;e<t.volumes.length;e++){let n=t.volumes[e].getRenderable().getBounds();o[e]=f([.5*(n[1]+n[0]),.5*(n[3]+n[2]),.5*(n[5]+n[4])],i)}let s=[...Array(t.volumes.length).keys()];s.sort((e,t)=>o[t]-o[e]);let c=[],l=s.length%a;for(let i=0;i<s.length;i++)c.push(t.volumes[s[i]]),c.length>=l&&(e.rayCastPass(r,n,c),c=[],l=a,t._firstGroup=!1)}else e.rayCastPass(r,n,t.volumes);if(t._volumeCopyQuad.setWebGPURenderer(n),t._useSmallViewport){let e=t._colorTextureView.getTexture().getWidth(),n=t._colorTextureView.getTexture().getHeight();t._copyUBO.setArray(`tscale`,[t._smallViewportWidth/e,t._smallViewportHeight/n])}else t._copyUBO.setArray(`tscale`,[1,1]);t._copyUBO.sendIfNeeded(i),t._copyEncoder.setColorTextureView(0,t.colorTextureView),t._copyEncoder.attachTextureViews(),t._copyEncoder.begin(r.getCommandEncoder()),n.scissorAndViewport(t._copyEncoder),t._volumeCopyQuad.prepareAndDraw(t._copyEncoder),t._copyEncoder.end()},e.delete=l.chain(()=>{t._animationRateSubscription&&(t._animationRateSubscription.unsubscribe(),t._animationRateSubscription=null)},e.delete),e.computeTiming=e=>{let n=e.getRenderable().getInteractor();t._lastScale??(t._lastScale=t.volumes[0].getRenderable().getMapper().getInitialInteractionScale()||1),t._useSmallViewport=!1,n.isAnimating()&&t._lastScale>1.5&&(t._useSmallViewport=!0),t._colorTexture.resize(e.getCanvas().width,e.getCanvas().height),t._animationRateSubscription||(t._animationRateSubscription=n.onAnimationFrameRateUpdate(()=>{let e=t.volumes[0].getRenderable().getMapper();if(e.getAutoAdjustSampleDistances()){let e=n.getRecentAnimationFrameRate();t._lastScale=t._lastScale*n.getDesiredUpdateRate()/e,t._lastScale>400&&(t._lastScale=400)}else t._lastScale=e.getImageSampleDistance()*e.getImageSampleDistance();t._lastScale<1.5&&(t._lastScale=1.5)}))},e.rayCastPass=(e,n,r)=>{let i=t._firstGroup?t._clearEncoder:t._mergeEncoder;i.attachTextureViews(),i.begin(e.getCommandEncoder());let a=t._colorTextureView.getTexture().getWidth(),o=t._colorTextureView.getTexture().getHeight();if(t._useSmallViewport){let n=e.getCanvas(),r=1/Math.sqrt(t._lastScale);t._smallViewportWidth=Math.ceil(r*n.width),t._smallViewportHeight=Math.ceil(r*n.height),a=t._smallViewportWidth,o=t._smallViewportHeight}i.getHandle().setViewport(0,0,a,o,0,1),i.getHandle().setScissorRect(0,0,a,o),t.fullScreenQuad.setWebGPURenderer(n),t.fullScreenQuad.setVolumes(r),t.fullScreenQuad.prepareAndDraw(i),i.end()},e.renderDepthBounds=(n,r)=>{e.updateDepthPolyData(n);let i=t._boundsPoly,a=i.getPoints(),o=i.getPolys(),s={hash:`vp${o.getMTime()}`,usage:q.Index,cells:o,numberOfPoints:a.getNumberOfPoints(),primitiveType:Ze.Triangles,representation:Xe.SURFACE},c=r.getDevice().getBufferManager().getBuffer(s);t._mapper.getVertexInput().setIndexBuffer(c),s={usage:q.PointArray,format:`float32x4`,hash:`vp${a.getMTime()}${o.getMTime()}`,dataArray:a,indexBuffer:c,packExtra:!0};let l=r.getDevice().getBufferManager().getBuffer(s);t._mapper.getVertexInput().addBuffer(l,[`vertexBC`]),t._mapper.setNumberOfVertices(l.getSizeInBytes()/l.getStrideInBytes()),e.drawDepthRange(n,r)},e.updateDepthPolyData=e=>{let n=!1;for(let e=0;e<t.volumes.length;e++){let r=t.volumes[e].getMTime();t._lastMTimes[e]&&r===t._lastMTimes[e]||(n=!0,t._lastMTimes[e]=r)}let r=e.getStabilizedTime();if((t._lastMTimes.length<=t.volumes.length||r!==t._lastMTimes[t.volumes.length])&&(n=!0,t._lastMTimes[t.volumes.length]=r),!n)return;let i=e.getStabilizedCenterByReference(),a=t.volumes.length*8,o=new Float64Array(a*3),s=t.volumes.length*12,c=new Uint16Array(s*4);for(let e=0;e<t.volumes.length;e++){t.volumes[e].getBoundingCubePoints(o,e*24);let n=e*12*4,r=e*8;for(let e=0;e<12;e++)c[n++]=3,c[n++]=r+J[e][0],c[n++]=r+J[e][1],c[n++]=r+J[e][2]}for(let e=0;e<o.length;e+=3)o[e]-=i[0],o[e+1]-=i[1],o[e+2]-=i[2];t._boundsPoly.getPoints().setData(o,3),t._boundsPoly.getPoints().modified(),t._boundsPoly.getPolys().setData(c,1),t._boundsPoly.getPolys().modified(),t._boundsPoly.modified()},e.drawDepthRange=(n,r)=>{t._depthRangeTexture.resizeToMatch(t.colorTextureView.getTexture()),t._depthRangeTexture2.resizeToMatch(t.colorTextureView.getTexture()),t._depthRangeEncoder.attachTextureViews(),e.setCurrentOperation(`volumeDepthRangePass`),n.setRenderEncoder(t._depthRangeEncoder),n.volumeDepthRangePass(!0),t._mapper.setWebGPURenderer(n),t._mapper.prepareToDraw(t._depthRangeEncoder),t._mapper.registerDrawCallback(t._depthRangeEncoder),n.volumeDepthRangePass(!1)},e.createDepthRangeEncoder=e=>{let n=e.getDevice();t._depthRangeEncoder=W.newInstance({label:`VolumePass DepthRange`}),t._depthRangeEncoder.setPipelineHash(`volr`),t._depthRangeEncoder.setReplaceShaderCodeFunction(e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<f32>`,`outColor1`),t.addOutput(`vec4<f32>`,`outColor2`);let n=t.getCode();n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`output.outColor1 = vec4<f32>(input.fragPos.z, 0.0, 0.0, 0.0);`,`output.outColor2 = vec4<f32>(stopval, 0.0, 0.0, 0.0);`]).result,t.setCode(n)}),t._depthRangeEncoder.setDescription({colorAttachments:[{view:null,clearValue:[0,0,0,0],loadOp:`clear`,storeOp:`store`},{view:null,clearValue:[1,1,1,1],loadOp:`clear`,storeOp:`store`}]}),t._depthRangeEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:`r16float`,blend:{color:{srcFactor:`one`,dstFactor:`one`,operation:`max`},alpha:{srcFactor:`one`,dstFactor:`one`,operation:`max`}}},{format:`r16float`,blend:{color:{srcFactor:`one`,dstFactor:`one`,operation:`min`},alpha:{srcFactor:`one`,dstFactor:`one`,operation:`min`}}}]}}),t._depthRangeTexture=M.newInstance({label:`volumePassMaxDepth`}),t._depthRangeTexture.create(n,{width:e.getCanvas().width,height:e.getCanvas().height,format:`r16float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING});let r=t._depthRangeTexture.createView(`maxTexture`);t._depthRangeEncoder.setColorTextureView(0,r),t._depthRangeTexture2=M.newInstance({label:`volumePassDepthMin`}),t._depthRangeTexture2.create(n,{width:e.getCanvas().width,height:e.getCanvas().height,format:`r16float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING});let a=t._depthRangeTexture2.createView(`minTexture`);t._depthRangeEncoder.setColorTextureView(1,a),t._mapper.setDevice(e.getDevice()),t._mapper.setTextureViews([t.depthTextureView])},e.createClearEncoder=e=>{t._colorTexture=M.newInstance({label:`volumePassColor`}),t._colorTexture.create(e.getDevice(),{width:e.getCanvas().width,height:e.getCanvas().height,format:`bgra8unorm`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_SRC}),t._colorTextureView=t._colorTexture.createView(`volumePassColorTexture`),t._colorTextureView.addSampler(e.getDevice(),{minFilter:`linear`,magFilter:`linear`}),t._clearEncoder=W.newInstance({label:`VolumePass Clear`}),t._clearEncoder.setColorTextureView(0,t._colorTextureView),t._clearEncoder.setDescription({colorAttachments:[{view:null,clearValue:[0,0,0,0],loadOp:`clear`,storeOp:`store`}]}),t._clearEncoder.setPipelineHash(`volpf`),t._clearEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:`bgra8unorm`,blend:{color:{srcFactor:`src-alpha`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}})},e.createCopyEncoder=e=>{t._copyEncoder=W.newInstance({label:`volumePassCopy`}),t._copyEncoder.setDescription({colorAttachments:[{view:null,loadOp:`load`,storeOp:`store`}]}),t._copyEncoder.setPipelineHash(`volcopypf`),t._copyEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:`rgba16float`,blend:{color:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}})},e.createMergeEncoder=e=>{t._mergeEncoder=W.newInstance({label:`volumePassMerge`}),t._mergeEncoder.setColorTextureView(0,t._colorTextureView),t._mergeEncoder.setDescription({colorAttachments:[{view:null,loadOp:`load`,storeOp:`store`}]}),t._mergeEncoder.setReplaceShaderCodeFunction(e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<f32>`,`outColor`);let n=t.getCode();n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`output.outColor = vec4<f32>(computedColor.rgb, computedColor.a);`]).result,t.setCode(n)}),t._mergeEncoder.setPipelineHash(`volpf`),t._mergeEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:`bgra8unorm`,blend:{color:{srcFactor:`src-alpha`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}})},e.setVolumes=n=>{if(!t.volumes||t.volumes.length!==n.length)t.volumes=[...n],e.modified();else for(let r=0;r<n.length;r++)if(n[r]!==t.volumes[r]){t.volumes=[...n],e.modified();return}},e.releaseGraphicsResources=()=>{t._animationRateSubscription&&(t._animationRateSubscription.unsubscribe(),t._animationRateSubscription=null),t._clearEncoder=null,t._mergeEncoder=null,t._copyEncoder=null,t._depthRangeEncoder=null,t._colorTexture=null,t._colorTextureView=null,t._depthRangeTexture=null,t._depthRangeTexture2=null,t._volumeCopyQuad=null,t.fullScreenQuad=null,t._copyUBO=null,t.colorTextureView=null,t.depthTextureView=null}}var tt={colorTextureView:null,depthTextureView:null,volumes:null};function nt(e,t,n={}){Object.assign(t,tt,n),O.extend(e,t,n),t._mapper=p.newInstance(),t._mapper.setFragmentShaderTemplate(Qe),t._mapper.getShaderReplacements().set(`replaceShaderVolumePass`,(e,t,n)=>{t.getShaderDescription(`fragment`).addBuiltinInput(`vec4<f32>`,`@builtin(position) fragPos`)}),t._boundsPoly=_.newInstance(),t._lastMTimes=[],l.setGet(e,t,[`colorTextureView`,`depthTextureView`]),et(e,t)}var rt={newInstance:l.newInstance(nt,`vtkWebGPUVolumePass`),extend:nt},it=`
//VTK::Mapper::Dec

//VTK::TCoord::Dec

//VTK::RenderEncoder::Dec

//VTK::IOStructs::Dec

@fragment
fn main(
//VTK::IOStructs::Input
)
//VTK::IOStructs::Output
{
  var output: fragmentOutput;

  var texCoord: vec2<i32> =
    vec2<i32>(i32(input.fragPos.x), i32(input.fragPos.y));
  var computedColor: vec4<f32> = clamp(
    textureLoad(opaquePassColorTexture, texCoord, 0),
    vec4<f32>(0.0),
    vec4<f32>(1.0)
  );

  //VTK::RenderEncoder::Impl
  return output;
}
`;function at(e,t){t.classHierarchy.push(`vtkForwardPass`),e.traverse=(n,r=null)=>{if(t.deleted)return;t._currentParent=r,e.setCurrentOperation(`buildPass`),n.traverse(e),t.opaquePass||(t.opaquePass=ze.newInstance());let i=n.getRenderable().getNumberOfLayers(),a=n.getChildren();for(let r=0;r<i;r++)for(let i=0;i<a.length;i++){let o=a[i],s=n.getRenderable().getRenderers()[i];s.getDraw()&&s.getLayer()===r&&(t.opaqueActorCount=0,t.translucentActorCount=0,t.volumes=[],e.setCurrentOperation(`queryPass`),o.traverse(e),e.setCurrentOperation(`cameraPass`),o.traverse(e),t.opaquePass.traverse(o,n),t.translucentActorCount>0&&(t.translucentPass||(t.translucentPass=We.newInstance()),t.translucentPass.setColorTextureView(t.opaquePass.getColorTextureView()),t.translucentPass.setDepthTextureView(t.opaquePass.getDepthTextureView()),t.translucentPass.traverse(o,n)),t.volumes.length>0&&(t.volumePass||(t.volumePass=rt.newInstance()),t.volumePass.setColorTextureView(t.opaquePass.getColorTextureView()),t.volumePass.setDepthTextureView(t.opaquePass.getDepthTextureView()),t.volumePass.setVolumes(t.volumes),t.volumePass.traverse(o,n)),e.finalPass(n,o))}},e.finalPass=(n,r)=>{t._finalBlitEncoder||e.createFinalBlitEncoder(n),t._finalBlitOutputTextureView.createFromTextureHandle(n.getCurrentTexture(),{depth:1,format:n.getPresentationFormat()}),t._finalBlitEncoder.attachTextureViews(),t._finalBlitEncoder.begin(n.getCommandEncoder()),r.scissorAndViewport(t._finalBlitEncoder),t._fullScreenQuad.prepareAndDraw(t._finalBlitEncoder),t._finalBlitEncoder.end()},e.createFinalBlitEncoder=e=>{t._finalBlitEncoder=W.newInstance({label:`forwardPassBlit`}),t._finalBlitEncoder.setDescription({colorAttachments:[{view:null,loadOp:`load`,storeOp:`store`}]}),t._finalBlitEncoder.setPipelineHash(`fpf`),t._finalBlitEncoder.setPipelineSettings({primitive:{cullMode:`none`},fragment:{targets:[{format:e.getPresentationFormat(),blend:{color:{srcFactor:`src-alpha`,dstFactor:`one-minus-src-alpha`},alpha:{srcFactor:`one`,dstFactor:`one-minus-src-alpha`}}}]}}),t._fsqSampler=y.newInstance({label:`finalPassSampler`}),t._fsqSampler.create(e.getDevice(),{minFilter:`linear`,magFilter:`linear`}),t._fullScreenQuad=d.newInstance(),t._fullScreenQuad.setDevice(e.getDevice()),t._fullScreenQuad.setPipelineHash(`fpfsq`),t._fullScreenQuad.setTextureViews([t.opaquePass.getColorTextureView()]),t._fullScreenQuad.setAdditionalBindables([t._fsqSampler]),t._fullScreenQuad.setFragmentShaderTemplate(it),t._fullScreenQuad.getShaderReplacements().set(`replaceShaderTCoord`,(e,t)=>{let n=t.getShaderDescription(`vertex`);n.hasOutput(`tcoordVS`)||n.addOutput(`vec2<f32>`,`tcoordVS`),t.getShaderDescription(`fragment`).addBuiltinInput(`vec4<f32>`,`@builtin(position) fragPos`)}),t._finalBlitOutputTextureView=oe.newInstance(),t._finalBlitEncoder.setColorTextureView(0,t._finalBlitOutputTextureView)},e.incrementOpaqueActorCount=()=>t.opaqueActorCount++,e.incrementTranslucentActorCount=()=>t.translucentActorCount++,e.addVolume=e=>{t.volumes.push(e)},e.releaseGraphicsResources=()=>{t.opaquePass?.releaseGraphicsResources?.(),t.translucentPass?.releaseGraphicsResources?.(),t.volumePass?.releaseGraphicsResources?.(),t.opaquePass=null,t.translucentPass=null,t.volumePass=null,t._finalBlitEncoder=null,t._finalBlitOutputTextureView=null,t._fullScreenQuad=null,t._fsqSampler=null}}var ot={opaqueActorCount:0,translucentActorCount:0,volumes:null,opaqueRenderEncoder:null,translucentPass:null,volumePass:null};function st(e,t,n={}){Object.assign(t,ot,n),O.extend(e,t,n),l.setGet(e,t,[`opaquePass`,`translucentPass`,`volumePass`]),at(e,t)}var ct={newInstance:l.newInstance(st,`vtkForwardPass`),extend:st},{VtkDataTypes:Y}=b;function lt(e,t){t.classHierarchy.push(`vtkWebGPUTextureManager`);function n(e){if(e.imageData){e.dataArray=e.imageData.getPointData().getScalars(),e.time=e.dataArray.getMTime(),e.nativeArray=e.dataArray.getData();let t=e.imageData.getDimensions();switch(e.width=t[0],e.height=t[1],e.depth=t[2],e.dataArray.getNumberOfComponents()){case 1:e.format=`r`;break;case 2:e.format=`rg`;break;default:e.format=`rgba`}switch(e.dataArray.getDataType()){case Y.UNSIGNED_CHAR:e.format+=`8unorm`;break;case Y.FLOAT:case Y.UNSIGNED_INT:case Y.INT:case Y.DOUBLE:case Y.UNSIGNED_SHORT:case Y.SHORT:default:e.format+=`16float`}}e.image&&(e.width=e.image.width,e.height=e.image.height,e.depth=1,e.format=`rgba8unorm`,e.flip=!0,e.usage=GPUTextureUsage.STORAGE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.RENDER_ATTACHMENT),e.jsImageData&&(e.width=e.jsImageData.width,e.height=e.jsImageData.height,e.depth=1,e.format=`rgba8unorm`,e.flip=!0,e.nativeArray=e.jsImageData.data,e.usage=GPUTextureUsage.STORAGE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.RENDER_ATTACHMENT),e.imageBitmap&&(e.width=e.imageBitmap.width,e.height=e.imageBitmap.height,e.depth=1,e.format=`rgba8unorm`,e.flip=!0,e.usage=GPUTextureUsage.STORAGE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.RENDER_ATTACHMENT),e.canvas&&(e.width=e.canvas.width,e.height=e.canvas.height,e.depth=1,e.format=`rgba8unorm`,e.flip=!0,e.usage=GPUTextureUsage.STORAGE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.RENDER_ATTACHMENT)}function r(e){let n=M.newInstance({label:e.label});return n.create(t.device,{width:e.width,height:e.height,depth:e.depth,format:e.format,usage:e.usage,mipLevel:e.mipLevel}),(e.nativeArray||e.image||e.canvas||e.imageBitmap)&&n.writeImageData(e),n}e.getTexture=e=>e.hash?t.device.getCachedObject(e.hash,r,e):r(e),e.getTextureForImageData=e=>{let r={time:e.getMTime()};return r.imageData=e,n(r),r.hash=r.time+r.format+r.mipLevel,t.device.getTextureManager().getTexture(r)},e.getTextureForVTKTexture=(e,r=void 0)=>{let i={time:e.getMTime(),label:r};return e.getInputData()?i.imageData=e.getInputData():e.getImage()?i.image=e.getImage():e.getJsImageData()?i.jsImageData=e.getJsImageData():e.getImageBitmap()?i.imageBitmap=e.getImageBitmap():e.getCanvas()&&(i.canvas=e.getCanvas()),n(i),i.mipLevel=e.getMipLevel(),i.hash=i.time+i.format+i.mipLevel,t.device.getTextureManager().getTexture(i)}}var ut={handle:null,device:null};function dt(e,t,n={}){Object.assign(t,ut,n),l.obj(e,t),l.setGet(e,t,[`device`]),lt(e,t)}var ft={newInstance:l.newInstance(dt),extend:dt},pt=class extends Map{constructor(){super(),this.registry=new FinalizationRegistry(e=>{let t=super.get(e);t&&t.deref&&t.deref()===void 0&&super.delete(e)})}getValue(e){let t=super.get(e);if(t){let n=t.deref();if(n!==void 0)return n;super.delete(e)}}setValue(e,t){let n;return t&&typeof t==`object`&&(n=new WeakRef(t),this.registry.register(t,e),super.set(e,n)),n}};function mt(e,t){t.classHierarchy.push(`vtkWebGPUDevice`),e.initialize=e=>{t.handle=e},e.createCommandEncoder=()=>t.handle.createCommandEncoder(),e.submitCommandEncoder=e=>{t.handle.queue.submit([e.finish()])},e.getShaderModule=e=>t.shaderCache.getShaderModule(e),e.getBindGroupLayout=e=>{if(!e.entries)return null;for(let t=0;t<e.entries.length;t++){let n=e.entries[t];n.binding=n.binding||0,n.visibility=n.visibility||GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT}let n=JSON.stringify(e);for(let e=0;e<t.bindGroupLayouts.length;e++)if(t.bindGroupLayouts[e].sval===n)return t.bindGroupLayouts[e].layout;let r=t.handle.createBindGroupLayout(e);return t.bindGroupLayouts.push({sval:n,layout:r}),r},e.getBindGroupLayoutDescription=e=>{for(let n=0;n<t.bindGroupLayouts.length;n++)if(t.bindGroupLayouts[n].layout===e)return t.bindGroupLayouts[n].sval;return vtkErrorMacro(`layout not found`),console.trace(),null},e.getPipeline=e=>e in t.pipelines?t.pipelines[e]:null,e.createPipeline=(n,r)=>{r.initialize(e,n),t.pipelines[n]=r},e.onSubmittedWorkDone=()=>t.handle.queue.onSubmittedWorkDone(),e.hasCachedObject=e=>t.objectCache.getValue(e),e.getCachedObject=(e,n,...r)=>{if(!e)return vtkErrorMacro(`attempt to cache an object without a hash`),null;let i=t.objectCache.getValue(e);if(i)return i;let a=n(...r);return t.objectCache.setValue(e,a),a}}var ht={handle:null,pipelines:null,shaderCache:null,bindGroupLayouts:null,bufferManager:null,textureManager:null};function gt(t,n,r={}){Object.assign(n,ht,r),g(t,n),e(t,n,[`handle`]),ce(t,n,[`bufferManager`,`shaderCache`,`textureManager`]),n.objectCache=new pt,n.shaderCache=i.newInstance(),n.shaderCache.setDevice(t),n.bindGroupLayouts=[],n.bufferManager=m.newInstance(),n.bufferManager.setDevice(t),n.textureManager=ft.newInstance(),n.textureManager.setDevice(t),n.pipelines={},mt(t,n)}var _t={newInstance:x(gt,`vtkWebGPUDevice`),extend:gt};function vt(e,t){t.classHierarchy.push(`vtkWebGPUHardwareSelectionPass`),e.traverse=(n,r)=>{if(t.deleted)return;t._currentParent=null,e.setCurrentOperation(`buildPass`),n.traverse(e);let i=n.getDevice();if(t.selectionRenderEncoder)t.colorTexture.resize(n.getCanvas().width,n.getCanvas().height),t.depthTexture.resizeToMatch(t.colorTexture);else{e.createRenderEncoder(),t.colorTexture=M.newInstance({label:`hardwareSelectorColor`}),t.colorTexture.create(i,{width:n.getCanvas().width,height:n.getCanvas().height,format:`rgba32uint`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.COPY_SRC});let r=t.colorTexture.createView(`hardwareSelectColorTexture`);t.selectionRenderEncoder.setColorTextureView(0,r),t.depthTexture=M.newInstance({label:`hardwareSelectorDepth`}),t.depthTexture.create(i,{width:n.getCanvas().width,height:n.getCanvas().height,format:`depth32float`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.COPY_SRC});let a=t.depthTexture.createView(`hardwareSelectDepthTexture`);t.selectionRenderEncoder.setDepthTextureView(a)}t.selectionRenderEncoder.attachTextureViews(),r.setRenderEncoder(t.selectionRenderEncoder),e.setCurrentOperation(`cameraPass`),r.traverse(e),e.setCurrentOperation(`opaquePass`),r.traverse(e)},e.createRenderEncoder=()=>{t.selectionRenderEncoder=W.newInstance({label:`HardwareSelectionPass`}),t.selectionRenderEncoder.setPipelineHash(`sel`),t.selectionRenderEncoder.setReplaceShaderCodeFunction(e=>{let t=e.getShaderDescription(`fragment`);t.addOutput(`vec4<u32>`,`outColor`);let n=t.getCode();n=i.substitute(n,`//VTK::Select::Impl`,[`  var compositeID: u32 = 0u;`,`  var attributeID: u32 = compositeID;`]).result,n=i.substitute(n,`//VTK::RenderEncoder::Impl`,[`output.outColor = vec4<u32>(mapperUBO.PropID, compositeID, attributeID + 1u, 0u);`]).result,t.setCode(n)});let e=t.selectionRenderEncoder.getDescription();e.colorAttachments[0].clearValue=[0,0,0,0],t.selectionRenderEncoder.setPipelineSettings({primitive:{cullMode:`none`},depthStencil:{depthWriteEnabled:!0,depthCompare:`greater`,format:`depth32float`},fragment:{targets:[{format:`rgba32uint`,blend:void 0}]}})}}var yt={selectionRenderEncoder:null,colorTexture:null,depthTexture:null};function bt(e,t,n={}){Object.assign(t,yt,n),O.extend(e,t,n),l.get(e,t,[`colorTexture`,`depthTexture`]),vt(e,t)}var xt={newInstance:l.newInstance(bt,`vtkWebGPUHardwareSelectionPass`),extend:bt},{SelectionContent:St,SelectionField:Ct}=P,{FieldAssociations:wt}=pe,{vtkErrorMacro:Tt}=l;function Et(e){return`${e.propID} ${e.compositeID}`}function X(e,t,n,r){let i=((n.height-t-1)*n.colorBufferWidth+e)*4+r;return n.colorValues[i]}function Z(e,t,n,r){let i=n<0?0:n;if(i===0){if(r[0]=t[0],r[1]=t[1],t[0]<0||t[0]>=e.width||t[1]<0||t[1]>=e.height)return null;let n=X(t[0],t[1],e,0);if(n<=0||n-1>=(e.props?.length??0))return null;let i={};i.propID=n-1,i.prop=e.props?.[i.propID];let a=X(t[0],t[1],e,1);(a<0||a>16777215)&&(a=0),i.compositeID=a-1;let o=X(t[0],t[1],e,2);if(o<1&&(o=a),i.attributeID=o-1,e.captureZValues){let n=(e.height-t[1]-1)*e.zbufferBufferWidth+t[0];i.zValue=e.depthValues[n],i.zValue=e.webGPURenderer.convertToOpenGLDepth(i.zValue),i.displayPosition=t}return i}let a=[t[0],t[1]],o=[0,0],s=Z(e,t,0,r);if(s)return s;for(let t=1;t<i;++t){for(let n=a[1]>t?a[1]-t:0;n<=a[1]+t;++n)if(o[1]=n,a[0]>=t&&(o[0]=a[0]-t,s=Z(e,o,0,r),s)||(o[0]=a[0]+t,s=Z(e,o,0,r),s))return s;for(let n=a[0]>=t?a[0]-(t-1):0;n<=a[0]+(t-1);++n)if(o[0]=n,a[1]>=t&&(o[1]=a[1]-t,s=Z(e,o,0,r),s)||(o[1]=a[1]+t,s=Z(e,o,0,r),s))return s}return r[0]=t[0],r[1]=t[1],null}function Dt(e,t,n){let r=[],i=0;return t.forEach((t,a)=>{let o=P.newInstance();switch(o.setContentType(St.INDICES),e){case wt.FIELD_ASSOCIATION_CELLS:o.setFieldType(Ct.CELL);break;case wt.FIELD_ASSOCIATION_POINTS:o.setFieldType(Ct.POINT);break;default:Tt(`Unknown field association`)}o.getProperties().propID=t.info.propID,o.getProperties().prop=t.info.prop,o.getProperties().compositeID=t.info.compositeID,o.getProperties().attributeID=t.info.attributeID,o.getProperties().pixelCount=t.pixelCount,n.captureZValues&&(o.getProperties().displayPosition=[t.info.displayPosition[0],t.info.displayPosition[1],t.info.zValue],o.getProperties().worldPosition=n.webGPURenderWindow.displayToWorld(t.info.displayPosition[0],t.info.displayPosition[1],t.info.zValue,n.renderer)),o.setSelectionList(t.attributeIDs),r[i]=o,i++}),r}function Ot(e,t,n,r,i){let a=Math.floor(t),o=Math.floor(n),s=Math.floor(r),c=Math.floor(i),l=new Map,u=[0,0];for(let t=o;t<=c;t++)for(let n=a;n<=s;n++){let r=Z(e,[n,t],0,u);if(r){let t=Et(r);if(!l.has(t))l.set(t,{info:r,pixelCount:1,attributeIDs:[r.attributeID]});else{let n=l.get(t);n.pixelCount++,e.captureZValues&&r.zValue<n.info.zValue&&(n.info=r),n.attributeIDs.indexOf(r.attributeID)===-1&&n.attributeIDs.push(r.attributeID)}}}return Dt(e.fieldAssociation,l,e)}function kt(e,t){t.classHierarchy.push(`vtkWebGPUHardwareSelector`),e.getPropIDForSelection=(e,n=null)=>{if(t._selectionPropMap.has(e))return t._selectionPropMap.get(e);let r=t._selectionProps.length;return t._selectionPropMap.set(e,r),t._selectionProps.push(n),r},e.endSelection=()=>{t.WebGPURenderer.setSelector(null)},e.getSourceDataAsync=async n=>{if(!n||!t._WebGPURenderWindow)return Tt(`Renderer and view must be set before calling Select.`),!1;t._WebGPURenderWindow.getRenderable().preRender(),t._WebGPURenderWindow.getInitialized()||(t._WebGPURenderWindow.initialize(),await new Promise(e=>{t._WebGPURenderWindow.onInitialized(e)}));let r=t._WebGPURenderWindow.getViewNodeFor(n);if(!r)return!1;let i=r.getSuppressClear(),a=r.getSelector();t._selectionPropMap.clear(),t._selectionProps=[],r.setSuppressClear(!0),r.setSelector(e);try{t._selectionPass.traverse(t._WebGPURenderWindow,r)}finally{r.setSelector(a),r.setSuppressClear(i)}let o=t._WebGPURenderWindow.getDevice(),s=t._selectionPass.getColorTexture(),c=t._selectionPass.getDepthTexture(),l={area:[0,0,s.getWidth()-1,s.getHeight()-1],captureZValues:t.captureZValues,fieldAssociation:t.fieldAssociation,props:[...t._selectionProps],renderer:n,webGPURenderer:r,webGPURenderWindow:t._WebGPURenderWindow,width:s.getWidth(),height:s.getHeight()};l.colorBufferWidth=16*Math.floor((l.width+15)/16),l.colorBufferSizeInBytes=l.colorBufferWidth*l.height*4*4;let u=A.newInstance({label:`hardwareSelectColorBuffer`});u.setDevice(o),u.create(l.colorBufferSizeInBytes,GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST);let d=t._WebGPURenderWindow.getCommandEncoder();d.copyTextureToBuffer({texture:s.getHandle()},{buffer:u.getHandle(),bytesPerRow:16*l.colorBufferWidth,rowsPerImage:l.height},{width:l.width,height:l.height,depthOrArrayLayers:1});let f;t.captureZValues&&(l.zbufferBufferWidth=64*Math.floor((l.width+63)/64),f=A.newInstance({label:`hardwareSelectDepthBuffer`}),f.setDevice(o),l.zbufferSizeInBytes=l.height*l.zbufferBufferWidth*4,f.create(l.zbufferSizeInBytes,GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST),d.copyTextureToBuffer({texture:c.getHandle(),aspect:`depth-only`},{buffer:f.getHandle(),bytesPerRow:4*l.zbufferBufferWidth,rowsPerImage:l.height},{width:l.width,height:l.height,depthOrArrayLayers:1})),o.submitCommandEncoder(d);let p=u.mapAsync(GPUMapMode.READ);if(t.captureZValues){let e=f.mapAsync(GPUMapMode.READ);await Promise.all([p,e]),l.depthValues=new Float32Array(f.getMappedRange().slice()),f.unmap()}else await p;return l.colorValues=new Uint32Array(u.getMappedRange().slice()),u.unmap(),l.generateSelection=(e,t,n,r)=>Ot(l,e,t,n,r),l}}var At={_selectionPropMap:null,_selectionProps:null};function jt(e,t,n={}){Object.assign(t,At,n),ue.extend(e,t,n),t._selectionPass=xt.newInstance(),t._selectionPropMap=new Map,t._selectionProps=[],l.setGet(e,t,[`_WebGPURenderWindow`]),l.moveToProtected(e,t,[`WebGPURenderWindow`]),kt(e,t)}var Mt={newInstance:l.newInstance(jt,`vtkWebGPUHardwareSelector`),extend:jt},{vtkErrorMacro:Nt,vtkWarningMacro:Pt}=l,Ft={position:`absolute`,top:0,left:0,width:`100%`,height:`100%`};function It(e,t){t.classHierarchy.push(`vtkWebGPURenderWindow`),e.getViewNodeFactory=()=>t.myFactory;function n(e,t=new Set){if(!e||t.has(e))return;t.add(e);let r=e.getChildren?.()||[];for(let e=0;e<r.length;e++){let i=r[e];i?.releaseGraphicsResources?.(),n(i,t)}}function r(){let n=e.onInitialized(()=>{n.unsubscribe(),t.deleted||e.traverseAllPasses()})}function i(n,i){if(t.deleted||i!==t.deviceGeneration||t.handlingDeviceLost)return;t.handlingDeviceLost=!0,t.deviceLostInfo=n;let a=n?.reason??`unknown`,o=n?.message||`WebGPU device was lost.`;Pt(`WebGPU device lost (${a}): ${o}`),e.releaseGraphicsResources(),e.invokeDeviceLost({reason:a,message:o,recoverable:a!==`destroyed`}),a!==`destroyed`&&(r(),e.initialize()),t.handlingDeviceLost=!1}function a(e,t){e.lost.then(e=>{i(e,t)})}let o=[0,0];function s(){t.renderable&&(t.size[0]!==o[0]||t.size[1]!==o[1])&&(o[0]=t.size[0],o[1]=t.size[1],t.canvas.setAttribute(`width`,t.size[0]),t.canvas.setAttribute(`height`,t.size[1]),e.recreateSwapChain()),t.viewStream&&t.viewStream.setSize(t.size[0],t.size[1]),t.canvas.style.display=t.useOffScreen?`none`:`block`,t.el&&(t.el.style.cursor=t.cursorVisibility?t.cursor:`none`),t.containerSize=null}e.onModified(s),e.recreateSwapChain=()=>{t.context&&(t.context.unconfigure(),t.presentationFormat=navigator.gpu.getPreferredCanvasFormat(t.adapter),t.context.configure({device:t.device.getHandle(),format:t.presentationFormat,alphaMode:`premultiplied`,usage:GPUTextureUsage.RENDER_ATTACHMENT|GPUTextureUsage.COPY_DST,width:t.size[0],height:t.size[1]}),t._configured=!0)},e.getCurrentTexture=()=>t.context.getCurrentTexture(),e.buildPass=n=>{if(n){if(!t.renderable)return;e.prepareNodes(),e.addMissingNodes(t.renderable.getRenderersByReference()),e.removeUnusedNodes(),e.initialize()}else t.initialized&&(t._configured||e.recreateSwapChain(),t.commandEncoder=t.device.createCommandEncoder())},e.initialize=()=>{if(!t.initializing){if(t.initializing=!0,t.deviceLostInfo=null,!navigator.gpu){Nt(`WebGPU is not enabled.`);return}e.create3DContextAsync().then(()=>{t.initialized=!0,t.deleted||e.invokeInitialized()})}},e.setContainer=n=>{t.el&&t.el!==n&&(t.canvas.parentNode!==t.el&&Nt(`Error: canvas parent node does not match container`),t.el.removeChild(t.canvas),t.el.contains(t.bgImage)&&t.el.removeChild(t.bgImage)),t.el!==n&&(t.el=n,t.el&&(t.el.appendChild(t.canvas),t.useBackgroundImage&&t.el.appendChild(t.bgImage)),e.modified())},e.getContainer=()=>t.el,e.getContainerSize=()=>{if(!t.containerSize&&t.el){let{width:e,height:n}=t.el.getBoundingClientRect();t.containerSize=[e,n]}return t.containerSize||t.size},e.getFramebufferSize=()=>t.size,e.create3DContextAsync=async()=>{t.adapter=await navigator.gpu.requestAdapter({powerPreference:`high-performance`}),t.deleted||(t.device=_t.newInstance(),t.device.initialize(await t.adapter.requestDevice({requiredLimits:{maxBufferSize:t.adapter.limits.maxBufferSize,maxStorageBufferBindingSize:t.adapter.limits.maxStorageBufferBindingSize,maxUniformBufferBindingSize:t.adapter.limits.maxUniformBufferBindingSize}})),t.deleted?t.device=null:(t.deviceGeneration+=1,a(t.device.getHandle(),t.deviceGeneration),t.context=t.canvas.getContext(`webgpu`)))},e.releaseGraphicsResources=()=>{if(t.renderPasses)for(let e=0;e<t.renderPasses.length;e++)t.renderPasses[e]?.releaseGraphicsResources?.();n(e);let r=O.newInstance();r.setCurrentOperation(`Release`),r.traverse(e,null),t.context&&t.context.unconfigure(),t.adapter=null,t.device=null,t.context=null,t.commandEncoder=null,t._configured=!1,t.initialized=!1,t.initializing=!1},e.setBackgroundImage=e=>{t.bgImage.src=e.src},e.setUseBackgroundImage=e=>{t.useBackgroundImage=e,t.useBackgroundImage&&!t.el.contains(t.bgImage)?t.el.appendChild(t.bgImage):!t.useBackgroundImage&&t.el.contains(t.bgImage)&&t.el.removeChild(t.bgImage)};async function c(n=t.imageFormat){let r=document.createElement(`canvas`),i=r.getContext(`2d`);r.width=t.canvas.width,r.height=t.canvas.height;let a=await e.getPixelsAsync(),o=new ImageData(a.colorValues,a.width,a.height);i.putImageData(o,0,0);let s=t.canvas.getBoundingClientRect();t.renderable.getRenderers().forEach(e=>{e.getViewProps().forEach(e=>{if(e.getContainer){let t=e.getContainer().getElementsByTagName(`canvas`);for(let e=0;e<t.length;e++){let n=t[e],r=n.getBoundingClientRect(),a=r.x-s.x,o=r.y-s.y;i.drawImage(n,a,o)}}})});let c=r.toDataURL(n);r.remove(),e.invokeImageReady(c)}e.captureNextImage=(n=`image/png`,{resetCamera:r=!1,size:i=null,scale:a=1}={})=>{if(t.deleted)return null;t.imageFormat=n;let o=t.notifyStartCaptureImage;return t.notifyStartCaptureImage=!0,t._screenshot={size:i||a!==1?i||t.size.map(e=>e*a):null},new Promise((n,i)=>{let a=e.onImageReady(i=>{if(t._screenshot.size===null)t.notifyStartCaptureImage=o,a.unsubscribe(),t._screenshot.placeHolder&&(t.size=t._screenshot.originalSize,e.modified(),t._screenshot.cameras&&t._screenshot.cameras.forEach(({restoreParamsFn:e,arg:t})=>e(t)),e.traverseAllPasses(),t.el.removeChild(t._screenshot.placeHolder),t._screenshot.placeHolder.remove(),t._screenshot=null),n(i);else{let n=document.createElement(`img`);if(n.style=Ft,n.src=i,t._screenshot.placeHolder=t.el.appendChild(n),t.canvas.style.display=`none`,t._screenshot.originalSize=t.size,t.size=t._screenshot.size,t._screenshot.size=null,e.modified(),r){let e=r!==!0;t._screenshot.cameras=t.renderable.getRenderers().map(t=>{let n=t.getActiveCamera(),i=n.get(`focalPoint`,`position`,`parallelScale`);return{resetCameraArgs:e?{renderer:t}:void 0,resetCameraFn:e?r:t.resetCamera,restoreParamsFn:n.set,arg:JSON.parse(JSON.stringify(i))}}),t._screenshot.cameras.forEach(({resetCameraFn:e,resetCameraArgs:t})=>e(t))}e.traverseAllPasses()}})})},e.traverseAllPasses=()=>{if(!t.deleted){if(t.initialized){if(t.renderPasses)for(let n=0;n<t.renderPasses.length;++n)t.renderPasses[n].traverse(e,null);t.commandEncoder&&(t.device.submitCommandEncoder(t.commandEncoder),t.commandEncoder=null,t.notifyStartCaptureImage&&t.device.onSubmittedWorkDone().then(()=>{c()}))}else{e.initialize();let t=e.onInitialized(()=>{t.unsubscribe(),e.traverseAllPasses()})}}},e.setViewStream=n=>{if(t.viewStream===n)return!1;if(t.subscription&&(t.subscription.unsubscribe(),t.subscription=null),t.viewStream=n,t.viewStream){let n=t.renderable.getRenderers()[0];n.getBackgroundByReference()[3]=0,e.setUseBackgroundImage(!0),t.subscription=t.viewStream.onImageReady(t=>e.setBackgroundImage(t.image)),t.viewStream.setSize(t.size[0],t.size[1]),t.viewStream.invalidateCache(),t.viewStream.render(),e.modified()}return!0},e.getUniquePropID=()=>t.nextPropID++,e.getPropFromID=e=>{for(let n=0;n<t.children.length;n++){let r=t.children[n].getPropFromID(e);if(r!==null)return r}return null},e.getPixelsAsync=async()=>{let e=t.device,n=t.renderPasses[0].getOpaquePass().getColorTexture(),r={width:n.getWidth(),height:n.getHeight()};r.colorBufferWidth=32*Math.floor((r.width+31)/32),r.colorBufferSizeInBytes=r.colorBufferWidth*r.height*8;let i=A.newInstance();i.setDevice(e),i.create(r.colorBufferSizeInBytes,GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST);let a=t.device.createCommandEncoder();a.copyTextureToBuffer({texture:n.getHandle()},{buffer:i.getHandle(),bytesPerRow:8*r.colorBufferWidth,rowsPerImage:r.height},{width:r.width,height:r.height,depthOrArrayLayers:1}),e.submitCommandEncoder(a),await i.mapAsync(GPUMapMode.READ),r.colorValues=new Uint16Array(i.getMappedRange().slice()),i.unmap();let o=new Uint8ClampedArray(r.height*r.width*4);for(let e=0;e<r.height;e++)for(let t=0;t<r.width;t++){let n=(e*r.width+t)*4,i=(e*r.colorBufferWidth+t)*4;o[n]=255*N.fromHalf(r.colorValues[i]),o[n+1]=255*N.fromHalf(r.colorValues[i+1]),o[n+2]=255*N.fromHalf(r.colorValues[i+2]),o[n+3]=255*N.fromHalf(r.colorValues[i+3])}return r.colorValues=o,r},e.createSelector=()=>{let t=Mt.newInstance();return t.setWebGPURenderWindow(e),t};let u=e.setSize;e.setSize=(t,n)=>{let r=u(t,n);return r&&e.invokeWindowResizeEvent({width:t,height:n}),r},e.delete=l.chain(e.delete,e.setViewStream)}var Lt={initialized:!1,initializing:!1,handlingDeviceLost:!1,deviceGeneration:0,deviceLostInfo:null,context:null,adapter:null,device:null,canvas:null,cursorVisibility:!0,cursor:`pointer`,containerSize:null,renderPasses:[],notifyStartCaptureImage:!1,imageFormat:`image/png`,useOffScreen:!1,useBackgroundImage:!1,nextPropID:1,xrSupported:!1,presentationFormat:null};function Rt(e,t,n={}){Object.assign(t,Lt,n),t.canvas=document.createElement(`canvas`),t.canvas.style.width=`100%`,t.bgImage=new Image,t.bgImage.style.position=`absolute`,t.bgImage.style.left=`0`,t.bgImage.style.top=`0`,t.bgImage.style.width=`100%`,t.bgImage.style.height=`100%`,t.bgImage.style.zIndex=`-1`,ie.extend(e,t,n),t.myFactory=o.newInstance(),t.renderPasses[0]=ct.newInstance(),t.selector||(t.selector=Mt.newInstance(),t.selector.setWebGPURenderWindow(e)),l.event(e,t,`imageReady`),l.event(e,t,`initialized`),l.event(e,t,`deviceLost`),l.get(e,t,[`commandEncoder`,`deviceLostInfo`,`device`,`presentationFormat`,`useBackgroundImage`,`xrSupported`]),l.setGet(e,t,[`initialized`,`context`,`canvas`,`device`,`renderPasses`,`notifyStartCaptureImage`,`cursor`,`useOffScreen`]),l.setGetArray(e,t,[`size`],2),l.event(e,t,`windowResizeEvent`),It(e,t)}var zt=l.newInstance(Rt,`vtkWebGPURenderWindow`);fe(`WebGPU`,zt),u(`vtkRenderWindow`,zt);var Bt=_e.extractURLParameters();function Vt(e,t){let n=e.invokeResize;delete e.invokeResize,t.renderWindow=T.newInstance(),t.renderer=ae.newInstance(),t.renderWindow.addRenderer(t.renderer),t._apiSpecificRenderWindow=t.renderWindow.newAPISpecificView(Bt.viewAPI??t.defaultViewAPI),t.renderWindow.addView(t._apiSpecificRenderWindow),t.interactor=se.newInstance(),t.interactor.setInteractorStyle(je.newInstance()),t.interactor.setView(t._apiSpecificRenderWindow),t.interactor.initialize(),e.setBackground=t.renderer.setBackground,e.setBackground(...t.background),e.resize=()=>{if(t.container){let e=t.container.getBoundingClientRect(),r=window.devicePixelRatio||1;t._apiSpecificRenderWindow.setSize(Math.floor(e.width*r),Math.floor(e.height*r)),n(),t.renderWindow.render()}},e.setContainer=e=>{t.container&&t.interactor.unbindEvents(t.container),t.container=e,t._apiSpecificRenderWindow.setContainer(t.container),t.container&&t.interactor.bindEvents(t.container)},e.delete=l.chain(e.setContainer,t._apiSpecificRenderWindow.delete,()=>{window.removeEventListener(`resize`,e.resize)},e.delete),t.listenWindowResize&&window.addEventListener(`resize`,e.resize),e.resize()}var Ht={background:[.32,.34,.43],listenWindowResize:!0,container:null};function Ut(e,t,n={}){Object.assign(t,Ht,n),l.obj(e,t),l.get(e,t,[`renderWindow`,`renderer`,`_apiSpecificRenderWindow`,`interactor`,`container`]),l.moveToProtected(e,t,[`_apiSpecificRenderWindow`]),l.event(e,t,`resize`),Vt(e,t)}var Wt={newInstance:l.newInstance(Ut),extend:Ut},Gt=[.925,.882,.788],Kt=[0,0,0,0],qt={front:{dir:[0,-1,0],up:[0,0,1]},top:{dir:[0,0,1],up:[0,-1,0]},side:{dir:[1,0,0],up:[0,0,1]}};function Jt(e,t){let n=new Uint32Array(t*4);for(let r=0;r<t;r++)n[r*4]=3,n[r*4+1]=e?e[r*3]:r*3,n[r*4+2]=e?e[r*3+1]:r*3+1,n[r*4+3]=e?e[r*3+2]:r*3+2;return n}function Yt(e){let t=Wt.newInstance({background:Kt,listenWindowResize:!1});t.setContainer(e);let n=t.getRenderer(),r=t.getRenderWindow(),i=n.getActiveCamera(),a=null,o=null,s=!1,c=null,l=()=>r.render(),u=()=>{t.resize()},d=new ResizeObserver(u);d.observe(e);function f(e){a&&(n.removeActor(a),a.delete(),o.delete());let t=_.newInstance();t.getPoints().setData(e.positions,3),t.getPolys().setData(Jt(e.indices,e.triangles)),e.normals&&t.getPointData().setNormals(b.newInstance({name:`Normals`,numberOfComponents:3,values:e.normals})),s=!!e.colors,s&&t.getPointData().setScalars(b.newInstance({name:`Colours`,numberOfComponents:3,values:e.colors})),o=ne.newInstance(),o.setInputData(t),o.setScalarVisibility(!1),o.setScalarModeToUsePointData(),o.setColorModeToDirectScalars(),a=w.newInstance(),a.setMapper(o);let r=a.getProperty();r.setColor(...Gt),r.setInterpolationToPhong(),r.setAmbient(.22),r.setDiffuse(.88),r.setSpecular(.22),r.setSpecularPower(28),n.addActor(a),c=e.bounds,p(`front`)}function p(e){let{dir:t,up:r}=qt[e]||qt.front,a=c?[(c[0]+c[1])/2,(c[2]+c[3])/2,(c[4]+c[5])/2]:[0,0,0];i.setFocalPoint(...a),i.setPosition(a[0]-t[0],a[1]-t[1],a[2]-t[2]),i.setViewUp(...r),i.orthogonalizeViewUp(),n.resetCamera(),i.elevation(-12),i.azimuth(12),i.orthogonalizeViewUp(),i.zoom(1.35),n.resetCameraClippingRange(),l()}function m(e){o&&(o.setScalarVisibility(e===`scan`&&s),l())}return{showMesh:f,look:p,setColourMode:m,render:l,resize:u,hasColours:()=>s,canvas:()=>e.querySelector(`canvas`),destroy(){d.disconnect(),a&&(n.removeActor(a),a.delete(),o.delete(),a=null,o=null),t.delete()}}}var Xt="var e=class extends Error{};const t=(e,t,n)=>{for(let r=0;r<n.length;r++)if(e[t+r]!==n.charCodeAt(r))return!1;return!0};function n(e,n=``){let r=new Uint8Array(e);if(r.length>=3&&t(r,0,`ply`))return`ply`;if(r.length>=84){let t=new DataView(e).getUint32(80,!0);if(r.length===84+t*50)return`stl`}let i=n.toLowerCase().split(`.`).pop();return i===`stl`||i===`ply`||i===`obj`?i:t(r,0,`solid`)?`stl`:`obj`}function r(e){let t=new Uint8Array(e);if(t.length>=84){let n=new DataView(e).getUint32(80,!0);if(t.length===84+n*50)return i(e,n)}return a(new TextDecoder().decode(t))}function i(t,n){if(n===0)throw new e(`This STL file holds no surface.`);let r=new DataView(t),i=new Float32Array(n*9),a=84,o=0;for(let e=0;e<n;e++){a+=12;for(let e=0;e<9;e++,a+=4)i[o++]=r.getFloat32(a,!0);a+=2}return{format:`stl`,positions:i,indices:null,colors:null}}function a(t){let n=/vertex\\s+([-+0-9.eE]+)\\s+([-+0-9.eE]+)\\s+([-+0-9.eE]+)/g,r=[];for(let e=n.exec(t);e;e=n.exec(t))r.push(+e[1],+e[2],+e[3]);if(r.length===0)throw new e(`This STL file holds no surface.`);if(r.length%9!=0)throw new e(`This STL file is incomplete.`);return{format:`stl`,positions:new Float32Array(r),indices:null,colors:null}}const o={char:1,int8:1,uchar:1,uint8:1,short:2,int16:2,ushort:2,uint16:2,int:4,int32:4,uint:4,uint32:4,float:4,float32:4,double:8,float64:8};function s(t,n,r,i){switch(r){case`char`:case`int8`:return t.getInt8(n);case`uchar`:case`uint8`:return t.getUint8(n);case`short`:case`int16`:return t.getInt16(n,i);case`ushort`:case`uint16`:return t.getUint16(n,i);case`int`:case`int32`:return t.getInt32(n,i);case`uint`:case`uint32`:return t.getUint32(n,i);case`float`:case`float32`:return t.getFloat32(n,i);case`double`:case`float64`:return t.getFloat64(n,i);default:throw new e(`This PLY file uses a kind of number CruDoc cannot read (${r}).`)}}function c(n){let r=new Uint8Array(n),i=Math.min(r.length,65536),a=-1;for(let e=0;e+10<=i;e++)if(r[e]===101&&t(r,e,`end_header`)){a=e;break}if(a<0)throw new e(`This PLY file has no readable header.`);let o=a;for(;o<r.length&&r[o]!==10;)o++;let s=new TextDecoder().decode(r.subarray(0,a)).split(`\n`).map(e=>e.trim()).filter(Boolean),c=``,l=[];for(let e of s){let t=e.split(/\\s+/);if(t[0]===`format`)c=t[1];else if(t[0]===`element`)l.push({name:t[1],count:Number(t[2])||0,props:[]});else if(t[0]===`property`&&l.length){let e=l[l.length-1];t[1]===`list`?e.props.push({name:t[4],list:!0,countType:t[2],valueType:t[3]}):e.props.push({name:t[2],list:!1,type:t[1]})}}if(!c)throw new e(`This PLY file does not say how it is written.`);if(![`ascii`,`binary_little_endian`,`binary_big_endian`].includes(c))throw new e(`This PLY file is written in a way CruDoc cannot read (${c}).`);return{format:c,elements:l,dataStart:o+1}}function l(t){let n={};for(let e of t.props)n[e.name]=e;let r=[`x`,`y`,`z`].map(e=>n[e]);if(r.some(e=>!e))throw new e(`This PLY file has no point positions.`);let i=(n.red?[`red`,`green`,`blue`]:[`r`,`g`,`b`]).map(e=>n[e]);return{xyz:r,rgb:i.every(Boolean)?i:null}}function u(t){let{format:n,elements:r,dataStart:i}=c(t),a=r.find(e=>e.name===`vertex`),o=r.find(e=>e.name===`face`);if(!a||!a.count)throw new e(`This PLY file holds no points.`);let s=l(a);return n===`ascii`?_(t,i,r,a,o,s):m(t,i,r,a,o,s,n===`binary_little_endian`)}const d=e=>e===`float`||e===`float32`||e===`double`||e===`float64`,f=e=>d(e.type)?255:1,p=e=>Math.max(0,Math.min(255,Math.round(e)));function m(t,n,r,i,a,c,l){let u=new DataView(t),d=n,m=0,_=/* @__PURE__ */ new Map;for(let t of i.props){if(t.list)throw new e(`This PLY file stores its points in a way CruDoc cannot read.`);let n=o[t.type];if(!n)throw new e(`This PLY file uses a kind of number CruDoc cannot read (${t.type}).`);_.set(t,m),m+=n}let v=i.count;if(d+v*m>t.byteLength)throw new e(`This PLY file is incomplete.`);let y=new Float32Array(v*3),b=c.rgb?new Uint8Array(v*3):null,x=c.rgb?f(c.rgb[0]):1;for(let e=0;e<v;e++){let t=d+e*m;for(let n=0;n<3;n++){let r=c.xyz[n];y[e*3+n]=s(u,t+_.get(r),r.type,l)}if(b)for(let n=0;n<3;n++){let r=c.rgb[n];b[e*3+n]=p(s(u,t+_.get(r),r.type,l)*x)}}d+=v*m;for(let e of r)if(e!==i){if(e===a)break;d=h(u,d,e,l,t.byteLength)}return{format:`ply`,positions:y,indices:a&&a.count?g(u,d,a,l,t.byteLength,v):null,colors:b}}function h(t,n,r,i,a){if(r.props.every(e=>!e.list)){let e=r.props.reduce((e,t)=>e+(o[t.type]||0),0);return n+r.count*e}for(let c=0;c<r.count;c++)for(let c of r.props)if(!c.list)n+=o[c.type]||0;else{if(n>=a)throw new e(`This PLY file is incomplete.`);n+=o[c.countType]+s(t,n,c.countType,i)*o[c.valueType]}return n}function g(t,n,r,i,a,c){let l=r.props.find(e=>e.list);if(!l)throw new e(`This PLY file does not list its triangles.`);let u=r.props.indexOf(l),d=r.props.slice(0,u).reduce((e,t)=>e+(o[t.type]||0),0),f=r.props.slice(u+1),p=[],m=o[l.valueType];for(let u=0;u<r.count;u++){if(n+=d,n+o[l.countType]>a)throw new e(`This PLY file is incomplete.`);let r=s(t,n,l.countType,i);if(n+=o[l.countType],n+r*m>a)throw new e(`This PLY file is incomplete.`);let u=[];for(let e=0;e<r;e++)u.push(s(t,n+e*m,l.valueType,i));n+=r*m,y(u,p,c);for(let e of f)n+=e.list?o[e.countType]+s(t,n,e.countType,i)*o[e.valueType]:o[e.type]||0}return p.length?new Uint32Array(p):null}function _(t,n,r,i,a,o){let s=v(new TextDecoder().decode(new Uint8Array(t,n))),c=i.count,l=new Float32Array(c*3),u=o.rgb?new Uint8Array(c*3):null,d=o.rgb?f(o.rgb[0]):1,m=new Map(i.props.map((e,t)=>[e,t]));for(let t=0;t<c;t++){let n=[];for(let e=0;e<i.props.length;e++)n.push(s.next());if(n.some(e=>e===void 0))throw new e(`This PLY file is incomplete.`);for(let e=0;e<3;e++)l[t*3+e]=n[m.get(o.xyz[e])];if(u)for(let e=0;e<3;e++)u[t*3+e]=p(n[m.get(o.rgb[e])]*d)}for(let e of r)if(e!==i){if(e===a)break;for(let t=0;t<e.count;t++)for(let t of e.props){let e=s.next();if(t.list)for(let t=0;t<e;t++)s.next()}}let h=[];if(a)for(let t=0;t<a.count;t++)for(let t of a.props){let n=s.next();if(n===void 0)throw new e(`This PLY file is incomplete.`);if(!t.list)continue;let r=[];for(let e=0;e<n;e++)r.push(s.next());y(r,h,c)}return{format:`ply`,positions:l,indices:h.length?new Uint32Array(h):null,colors:u}}function v(e){let t=0,n=e.length;return{next(){for(;t<n&&e.charCodeAt(t)<=32;)t++;if(t>=n)return;let r=t;for(;t<n&&e.charCodeAt(t)>32;)t++;return Number(e.slice(r,t))}}}function y(e,t,n){for(let r=2;r<e.length;r++){let i=e[0],a=e[r-1],o=e[r];i>=0&&a>=0&&o>=0&&i<n&&a<n&&o<n&&t.push(i,a,o)}}function b(t){let n=new TextDecoder().decode(new Uint8Array(t)),r=[],i=[];for(let e of n.split(`\n`)){let t=e.trim();if(!t||t.charCodeAt(0)===35)continue;let n=t.split(/\\s+/);if(n[0]===`v`)r.push(+n[1],+n[2],+n[3]);else if(n[0]===`f`){let e=[];for(let t=1;t<n.length;t++){let i=parseInt(n[t].split(`/`)[0],10);Number.isNaN(i)||e.push(i>0?i-1:r.length/3+i)}i.push(e)}}if(!r.length)throw new e(`This OBJ file holds no points.`);let a=[];for(let e of i)y(e,a,r.length/3);return{format:`obj`,positions:new Float32Array(r),indices:a.length?new Uint32Array(a):null,colors:null}}function x(e){if(!e.length)return[0,0,0,0,0,0];let t=[1/0,-1/0,1/0,-1/0,1/0,-1/0];for(let n=0;n<e.length;n+=3)for(let r=0;r<3;r++){let i=e[n+r];i<t[r*2]&&(t[r*2]=i),i>t[r*2+1]&&(t[r*2+1]=i)}return t}function S(e,t){let n=new Float32Array(e.length),r=t?t.length:e.length/3;for(let i=0;i+2<r;i+=3){let r=(t?t[i]:i)*3,a=(t?t[i+1]:i+1)*3,o=(t?t[i+2]:i+2)*3,s=e[a]-e[r],c=e[a+1]-e[r+1],l=e[a+2]-e[r+2],u=e[o]-e[r],d=e[o+1]-e[r+1],f=e[o+2]-e[r+2],p=c*f-l*d,m=l*u-s*f,h=s*d-c*u;n[r]+=p,n[r+1]+=m,n[r+2]+=h,n[a]+=p,n[a+1]+=m,n[a+2]+=h,n[o]+=p,n[o+1]+=m,n[o+2]+=h}for(let e=0;e<n.length;e+=3){let t=Math.hypot(n[e],n[e+1],n[e+2]);t>0&&(n[e]/=t,n[e+1]/=t,n[e+2]/=t)}return n}function C(e,t=null){let n=x(e),r=131071/(Math.max(n[1]-n[0],n[3]-n[2],n[5]-n[4])||1),i=/* @__PURE__ */ new Map,a=e.length/3,o=new Uint32Array(a),s=new Float32Array(e.length),c=t?new Uint8Array(t.length):null,l=0;for(let u=0;u<a;u++){let a=Math.round((e[u*3]-n[0])*r),d=Math.round((e[u*3+1]-n[2])*r),f=Math.round((e[u*3+2]-n[4])*r),p=(a*131072+d)*131072+f,m=i.get(p);if(m===void 0&&(m=l++,i.set(p,m),s[m*3]=e[u*3],s[m*3+1]=e[u*3+1],s[m*3+2]=e[u*3+2],c))for(let e=0;e<3;e++)c[m*3+e]=t[u*3+e];o[u]=m}return{positions:s.slice(0,l*3),colors:c?c.slice(0,l*3):null,indices:o}}function w(t,i=``){let a=n(t,i),{positions:o,indices:s,colors:c}=a===`ply`?u(t):a===`obj`?b(t):r(t);if(!o.length)throw new e(`This file holds no surface.`);if(o.length%3!=0)throw new e(`This file is incomplete.`);let l=!1;if(!s){if(o.length%9!=0)throw new e(`This file is incomplete.`);if(o.length/3<=15e5){let e=C(o,c);o=e.positions,c=e.colors,s=e.indices,l=!0}}let d=s?s.length/3:o.length/9;if(!d)throw new e(`This file holds no triangles.`);return{format:a,positions:o,indices:s,normals:S(o,s),colors:c,points:o.length/3,triangles:d,bounds:x(o),welded:l}}self.onmessage=t=>{let{id:n,buffer:r,name:i}=t.data;try{let e=performance.now(),t=w(r,i),a=Math.round(performance.now()-e),o={id:n,format:t.format,positions:t.positions,indices:t.indices,normals:t.normals,colors:t.colors,points:t.points,triangles:t.triangles,bounds:t.bounds,welded:t.welded,parseMs:a},s=[t.positions,t.normals,t.indices,t.colors].filter(Boolean).map(e=>e.buffer);self.postMessage(o,s)}catch(t){self.postMessage({id:n,error:t instanceof e?t.message:`CruDoc could not read this 3D file.`})}};",Zt=typeof self<`u`&&self.Blob&&new Blob([`URL.revokeObjectURL(import.meta.url);`,Xt],{type:`text/javascript;charset=utf-8`});function Qt(e){let t;try{if(t=Zt&&(self.URL||self.webkitURL).createObjectURL(Zt),!t)throw``;let n=new Worker(t,{type:`module`,name:e?.name});return n.addEventListener(`error`,()=>{(self.URL||self.webkitURL).revokeObjectURL(t)}),n}catch{return new Worker(`data:text/javascript;charset=utf-8,`+encodeURIComponent(Xt),{type:`module`,name:e?.name})}}function Q(e,t={},...n){let r=document.createElement(e);for(let[e,n]of Object.entries(t))n!=null&&(e===`class`?r.className=n:e===`text`?r.textContent=n:e.startsWith(`on`)?r.addEventListener(e.slice(2),n):r.setAttribute(e,n));return n.flat().forEach(e=>e!=null&&e!==!1&&r.append(e)),r}var $=e=>e.toLocaleString(`en-US`),$t=e=>e<1024?`${e} B`:e<1048576?`${(e/1024).toFixed(1)} KB`:`${(e/1048576).toFixed(1)} MB`,en=e=>`${Math.round(e[1]-e[0])} × ${Math.round(e[3]-e[2])} × ${Math.round(e[5]-e[4])} mm`;function tn(e,{title:t,name:n,badge:r}){let i=Q(`button`,{class:`ico`,type:`button`,title:`Back`,"aria-label":`Back`},D(`back`,16)),a=Q(`div`,{class:`title`,text:t||n||`3D scan`}),o=Q(`div`,{class:`chip`,text:n||``}),s=Q(`button`,{class:`ico`,type:`button`,title:`Reset the view (R)`,"aria-label":`Reset the view`},D(`reset`,16)),c=(e,t,n)=>{let r=e.map(([,e])=>Q(`button`,{class:`seg-btn`,type:`button`,text:e}));return r.forEach((i,a)=>{i.classList.toggle(`on`,e[a][0]===n),i.addEventListener(`click`,()=>{r.forEach(e=>e.classList.toggle(`on`,e===i)),t(e[a][0])})}),{el:Q(`div`,{class:`seg`},r),buttons:r}},l=Q(`div`,{class:`stage`}),u=Q(`div`,{class:`hint`,text:`Drag to rotate · scroll to zoom · middle-drag to move`}),d=Q(`div`,{class:`msg`,hidden:`hidden`}),f=Q(`div`,{class:`note`}),p=Q(`i`),m=Q(`div`,{class:`progress`},f,Q(`div`,{class:`track`},p)),h=Q(`div`,{class:`status`}),g=r?Q(`div`,{class:r===`Anonymized`?`badge good`:`badge`},D(r===`Anonymized`?`shield`:`eye`,13),Q(`span`,{text:r})):null,_=c([[`front`,`Front`],[`top`,`Top`],[`side`,`Side`]],e=>b.onLook(e),`front`),v=c([[`ivory`,`Ivory`],[`scan`,`Scan colour`]],e=>b.onColour(e),`ivory`);v.el.hidden=!0;let y=Q(`header`,{class:`topbar`},i,a,o,Q(`span`,{class:`grow`}),_.el,v.el,s,g);e.append(Q(`div`,{class:`app`},y,Q(`main`,{class:`main`},l,u,d,m),Q(`footer`,{class:`statusbar`},h)));let b={stage:l,onLook:()=>{},onColour:()=>{},onBack:()=>{},onReset:()=>{},setChip:e=>o.textContent=e,setStatus:e=>h.textContent=e,showColours:()=>v.el.hidden=!1,busy(e,t){m.hidden=!1,f.textContent=e,p.style.width=t==null?``:`${Math.round(t*100)}%`,p.classList.toggle(`waiting`,t==null)},done(){m.hidden=!0,u.classList.add(`show`),setTimeout(()=>u.classList.remove(`show`),4e3)},fail(e){m.hidden=!0,d.hidden=!1,d.textContent=e}};return i.addEventListener(`click`,()=>b.onBack()),s.addEventListener(`click`,()=>b.onReset()),b}async function nn(e,t){let n=await fetch(e);if(!n.ok)throw Error(`This 3D file could not be read from the clinic computer.`);let r=Number(n.headers.get(`content-length`))||0;if(!n.body||!r)return{buffer:await n.arrayBuffer(),total:r};let i=[],a=n.body.getReader(),o=0;for(;;){let{done:e,value:n}=await a.read();if(e)break;i.push(n),o+=n.length,t(o/r)}let s=new Uint8Array(o),c=0;for(let e of i)s.set(e,c),c+=e.length;return{buffer:s.buffer,total:o}}function rn(e,t){return new Promise((n,r)=>{let i=new Qt;i.onmessage=e=>{i.terminate(),e.data.error?r(Error(e.data.error)):n(e.data)},i.onerror=()=>{i.terminate(),r(Error(`CruDoc could not read this 3D file.`))},i.postMessage({id:1,buffer:e,name:t},[e])})}async function an(e){let t=on(),n=e.get(`name`)||``,r=tn(document.getElementById(`app`),{title:e.get(`title`)||``,name:n,badge:e.get(`badge`)||``});(e.get(`reduced`)===`1`||matchMedia(`(prefers-reduced-motion: reduce)`).matches)&&document.documentElement.classList.add(`reduced`),t({type:`boot`,version:re});let i=Yt(r.stage),a=()=>t({type:`close`});r.onBack=a,r.onLook=e=>i.look(e),r.onColour=e=>i.setColourMode(e),r.onReset=()=>i.look(`front`),window.addEventListener(`keydown`,e=>{e.key===`Escape`?a():(e.key===`r`||e.key===`R`)&&i.look(`front`)});let o=e.get(`file`);if(!o)r.fail(`No 3D file was given to open.`);else try{r.busy(`Opening the scan`,0);let{buffer:a,total:s}=await nn(o,e=>r.busy(`Opening the scan`,e));r.busy(`Preparing the surface`,null);let c=await rn(a,n);i.showMesh(c);let l=c.format.toUpperCase();r.setChip([n,`${$(c.triangles)} triangles`].filter(Boolean).join(` · `)),r.setStatus([l,$t(s),`${$(c.triangles)} triangles`,`${$(c.points)} points`,en(c.bounds)].join(`  ·  `)),c.colors&&r.showColours(),r.done(),t({type:`shown`,triangles:c.triangles,points:c.points,format:c.format,parseMs:c.parseMs}),e.has(`debug`)&&(window.__mesh={scene:i,mesh:{...c,positions:null,indices:null,normals:null,colors:null},triangles:c.triangles,points:c.points})}catch(e){let n=e&&e.message?e.message:`CruDoc could not open this 3D file.`;r.fail(n),t({type:`error`,message:n})}}function on(){let e=[],t=!!(window.flutter_inappwebview&&typeof window.flutter_inappwebview.callHandler==`function`),n=e=>{try{window.flutter_inappwebview.callHandler(`cbct`,e)}catch{}};return window.addEventListener(`flutterInAppWebViewPlatformReady`,()=>{for(t=!0;e.length;)n(e.shift())},{once:!0}),r=>{console.log(`[mesh->flutter]`,JSON.stringify(r)),t?n(r):e.push(r)}}console.log(`Scan viewer booted`),an(new URLSearchParams(location.search));