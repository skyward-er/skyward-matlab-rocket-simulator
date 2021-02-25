function [dY, parout] = main_descent(t, Y, settings, uw, vw, ww, para1, para2, t0p, uncert, Hour, Day)

%% RECALLING THE STATE
% Rocket state
x_rocket = Y(1);
y_rocket = Y(2);
z_rocket = Y(3);
u_rocket = Y(4);
v_rocket = Y(5);
w_rocket = Y(6);
p_rocket = Y(7);
q_rocket = Y(8);
r_rocket = Y(9);
q0_rocket = Y(10);
q1_rocket = Y(11);
q2_rocket = Y(12);
q3_rocket = Y(13);
m_rocket = settings.ms;
Ixx = settings.Ixxe;
Iyy = settings.Iyye;
Izz = settings.Izze;

Q_rocket = [ q0_rocket q1_rocket q2_rocket q3_rocket];
Q_conj_rocket = [ q0_rocket -q1_rocket -q2_rocket -q3_rocket];
normQ_rocket = norm(Q_rocket);

if abs(normQ_rocket-1) > 0.1
    Q_rocket = Q_rocket/normQ_rocket;
end

% first parachute state
x_para1 = Y(14);
y_para1 = Y(15);
z_para1 = Y(16);
u_para1 = Y(17);
v_para1 = Y(18);
w_para1 = Y(19);

m_para1 = settings.mnc + para1.mass;

% second parachute state
x_para2 = Y(20);
y_para2 = Y(21);
z_para2 = Y(22);
u_para2 = Y(23);
v_para2 = Y(24);
w_para2 = Y(25);

m_para2 = para2.mass;

%% ADDING WIND (supposed to be added in NED axes);
if settings.wind.model
    if settings.stoch.N > 1
        [uw,vw,ww] = wind_matlab_generator(settings,z_rocket,t,Hour,Day);
    else
        [uw,vw,ww] = wind_matlab_generator(settings,z_rocket,t);
    end 
elseif settings.wind.input
    [uw,vw,ww] = wind_input_generator(settings,z_rocket,uncert);
end

wind = quatrotate(Q_rocket,[uw vw ww]);

% Rocket (BODY) relative velocities (plus wind);
ur_rocket = u_rocket - wind(1);
vr_rocket = v_rocket - wind(2);
wr_rocket = w_rocket - wind(3);

Vels_rocket = quatrotate(Q_conj_rocket,[u_rocket v_rocket w_rocket]);
V_norm_rocket = norm([ur_rocket vr_rocket wr_rocket]);

% Parachute 1 (NED) relative velocities (plus wind) 
ur_para1 = u_para1 - uw;
vr_para1 = v_para1 - vw;
wr_para1 = w_para1 - ww;

Vels_para1 = [u_para1 v_para1 w_para1];
Vrel_para1 = [ur_para1 vr_para1 wr_para1];
V_norm_para1 = norm([ur_para1 vr_para1 wr_para1]);

% Parachute 2 (NED) relative velocities (plus wind) 
ur_para2 = u_para2 - uw;
vr_para2 = v_para2 - vw;
wr_para2 = w_para2 - ww;

Vels_para2 = [u_para2 v_para2 w_para2];
Vrel_para2 = [ur_para2 vr_para2 wr_para2];
V_norm_para2 = norm([ur_para2 vr_para2 wr_para2]);

%% PARACHUTE 1 REFERENCE FRAME
% The parachutes are approximated as rectangular surfaces with the normal
% vector perpendicular to the relative velocity
if all(abs(Vrel_para1) < 1e-3)
    t_vers1 = [0, 0, -1];
else
    t_vers1 = -Vrel_para1/V_norm_para1;
end

if all(abs(Vrel_para2) < 1e-3)
    t_vers2 = [0, 0, -1];
else
    t_vers2 = -Vrel_para2/V_norm_para2;
end

%% CONSTANTS
% Everything related to empty condition (descent-fase)
g = 9.80655;                                                                  % [N/kg] module of gravitational field at zero
T = 0;                                                                        % No Thrust

%% ATMOSPHERE DATA
% since z_rocket is similar to z_para, atmospherical data will be computed
% on z_rocket
[~, a, P, rho] = atmosisa(-z_rocket+settings.z0);
M_rocket = V_norm_rocket/a;
M_value_rocket = M_rocket;

%% RELATIVE POSITION AND VELOCITY VECTORS (PARA1)
posPara1 = [x_para1 y_para1 z_para1];
posPara2 = [x_para2 y_para2 z_para2];
posRocket = [x_rocket y_rocket z_rocket];
posDepl = posRocket + quatrotate(Q_conj_rocket,[(settings.xcg(2)-settings.Lnc) 0 0]);
posRelDrgMain = posPara1 - posPara2;
posRelDrgDepl = posPara1 - posDepl;
posRelMainDepl = posPara2 - posDepl;
if norm(posRelDrgMain) < 1e-3
    posRelDrgMain = [0, 0, -1e-3];
end
if norm(posRelDrgDepl) < 1e-3
    posRelDrgDepl = [0, 0, -1e-3];
end
if norm(posRelMainDepl) < 1e-3
    posRelMainDepl = [0, 0, -1e-3];
end
posRelDrgMain_vers = posRelDrgMain/norm(posRelDrgMain);
posRelDrgDepl_vers = posRelDrgDepl/norm(posRelDrgDepl);
posRelMainDepl_vers = posRelMainDepl/norm(posRelMainDepl);
%% CHORD TENSION (ELASTIC-DAMPING MODEL)
if norm(posRelDrgMain) > para1.L
    T_chordRel = (norm(posRelDrgMain) - para1.L)* para1.K;
else
    T_chordRel = 0;
end

if norm(posRelDrgDepl) > (para2.L + para1.L)                      % [N] Chord tension (elastic-damping model)
    T_chord1 = (norm(posRelDrgDepl) - (para2.L + para1.L))* para1.K;
else
    T_chord1 = 0;
end

if norm(posRelMainDepl) > para2.L                     % [N] Chord tension (elastic-damping model)
    T_chord2 = (norm(posRelMainDepl) - para2.L)* para2.K;
else
    T_chord2 = 0;
end 

%% PARACHUTES FORCES PARA 1
% computed in the NED-frame reference system
S_para1 = para1.S;                                                   % [m^2]   Surface
CD_para1 = para1.CD;
D0 = sqrt(4*para1.S/pi);
t0 = para1.nf * D0/V_norm_para1;
tx = t0 * para1.CX^(1/para1.m);
SCD0_1 = S_para1*CD_para1;

dt = t-t0p(1);

if dt < 0
    SCD_para1 = 0;
elseif dt < tx
    SCD_para1 = SCD0_1 * (dt/t0)^para1.m;
else
    SCD_para1 = SCD0_1 * (1+(para1.CX-1)*exp(-2*(dt-tx)/t0));
end

D_para1 = 0.5*rho*V_norm_para1^2*SCD_para1*t_vers1';
Fg_para1 = [0 0 m_para1*g]';                                                   % [N] Gravitational Force vector

Ft_chordRel_para1 = -T_chordRel * posRelDrgMain_vers;
Ft_chord_para1 = -T_chord1 * posRelDrgDepl_vers;

F_para1 = D_para1 + Fg_para1 + Ft_chord_para1' + Ft_chordRel_para1';                          % [N] (BODY) total forces vector

%% PARACHUTE FORCES PARA 2
% computed in the NED-frame reference system
S_para2 = para2.S;                                                   % [m^2]   Surface
CD_para2 = para2.CD;
D0 = sqrt(4*para2.S/pi);
t0 = para2.nf * D0/V_norm_para2;
tx = t0 * para2.CX^(1/para2.m);
SCD0_2 = S_para2*CD_para2;

dt = t-t0p(2);

if dt < 0
    SCD_para2 = 0;
elseif dt < tx
    SCD_para2 = SCD0_2 * (dt/t0)^para2.m;
else
    SCD_para2 = SCD0_2 * (1+(para2.CX-1)*exp(-2*(dt-tx)/t0));
end

D_para2 = 0.5*rho*V_norm_para2^2*SCD_para2*t_vers2';
Fg_para2 = [0 0 m_para2*g]';                                                    % [N] Gravitational Force vector

Ft_chordRel_para2 = T_chordRel * posRelDrgMain_vers;
Ft_chord_para2 = -T_chord2 * posRelMainDepl_vers;

F_para2 = D_para2 + Fg_para2 + Ft_chord_para2' + Ft_chordRel_para2';                          % [N] (BODY) total forces vector

%% ROCKET FORCES
% computed in the body-frame reference system
Fg_rocket = quatrotate(Q_rocket,[0 0 m_rocket*g])';                           % [N] force due to the gravity

Ft_chord_rocket1 = T_chord1 * quatrotate(Q_rocket,posRelDrgDepl_vers);                                  % [N] Chord tension vector (rocket view)
Ft_chord_rocket2 = T_chord2 * quatrotate(Q_rocket,posRelMainDepl_vers);

F_rocket = Fg_rocket + Ft_chord_rocket1' + Ft_chord_rocket2';                                      % [N] (NED) total forces vector

%% ROCKET STATE DERIVATIVES
% velocity (BODY frame)
du_rocket = F_rocket(1)/m_rocket-q_rocket*w_rocket+r_rocket*v_rocket;
dv_rocket = F_rocket(2)/m_rocket-r_rocket*u_rocket+p_rocket*w_rocket;
dw_rocket = F_rocket(3)/m_rocket-p_rocket*v_rocket+q_rocket*u_rocket;

% Rotation
b = [(settings.xcg(2)-settings.Lnc) 0 0];
Momentum = cross(b, (Ft_chord_rocket1+Ft_chord_rocket2));                                          % [Nm] Chord tension moment

dp_rocket = (Iyy-Izz)/Ixx*q_rocket*r_rocket + Momentum(1)/Ixx;
dq_rocket = (Izz-Ixx)/Iyy*p_rocket*r_rocket + Momentum(2)/Iyy;
dr_rocket = (Ixx-Iyy)/Izz*p_rocket*q_rocket + Momentum(3)/Izz;

% Quaternion
OM = 1/2* [ 0 -p_rocket -q_rocket -r_rocket  ;
            p_rocket  0  r_rocket -q_rocket  ;
            q_rocket -r_rocket  0  p_rocket  ;
            r_rocket  q_rocket -p_rocket  0 ];

dQQ_rocket = OM*Q_rocket';

%% PARACHUTE STATE DERIVATIVES
% velocity (NED frame)
% para 1
du_para1 = F_para1(1)/m_para1;
dv_para1 = F_para1(2)/m_para1;
dw_para1 = F_para1(3)/m_para1;

% para 2
du_para2 = F_para2(1)/m_para2;
dv_para2 = F_para2(2)/m_para2;
dw_para2 = F_para2(3)/m_para2;

%% FINAL DERIVATIVE STATE ASSEMBLING
dY(1:3) = Vels_rocket;
dY(4) = du_rocket;
dY(5) = dv_rocket;
dY(6) = dw_rocket;
dY(7) = dp_rocket;
dY(8) = dq_rocket;
dY(9) = dr_rocket;
dY(10:13) = dQQ_rocket;
dY(14:16) = Vels_para1;
dY(17) = du_para1;
dY(18) = dv_para1;
dY(19) = dw_para1;
dY(20:22) = Vels_para2;
dY(23) = du_para2;
dY(24) = dv_para2;
dY(25) = dw_para2;
dY(26:28) = [p_rocket q_rocket r_rocket];
dY=dY';

%% SAVING THE QUANTITIES FOR THE PLOTS
% Drogue data
parout.integration.t = t;

parout.interp.M = M_value_rocket;
parout.interp.alt = -z_rocket;
parout.interp.alpha = 0;
parout.interp.beta = 0;

parout.wind.NED_wind = [uw, vw, ww];
parout.wind.body_wind = wind;

parout.velocities = Vels_rocket;

parout.forces.T = T;
parout.forces.T_chord1 = T_chordRel;
parout.forces.T_chord2 = T_chord2;

parout.SCD1 = SCD_para1/SCD0_1;
parout.SCD2 = SCD_para2/SCD0_2;

parout.air.rho = rho;
parout.air.P = P;

parout.accelerations.body_acc = [du_rocket, dv_rocket, dw_rocket];
parout.accelerations.ang_acc = [dp_rocket, dq_rocket, dr_rocket];