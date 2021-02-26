function [dY, parout] = drogue_descent(t, Y, settings, uw, vw, ww, para, t0p, uncert, Hour, Day)
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
m_rocket = settings.ms - settings.para(para(1)).mass;
Ixx = settings.Ixxe;
Iyy = settings.Iyye;
Izz = settings.Izze;

Q_rocket = [ q0_rocket q1_rocket q2_rocket q3_rocket];
Q_conj_rocket = [ q0_rocket -q1_rocket -q2_rocket -q3_rocket];
normQ_rocket = norm(Q_rocket);

if abs(normQ_rocket-1) > 0.1
    Q_rocket = Q_rocket/normQ_rocket;
end

% parachute state
x_para = Y(17);
y_para = Y(18);
z_para = Y(19);
u_para = Y(20);
v_para = Y(21);
w_para = Y(22);

m_para = settings.mnc + settings.para(para).mass;

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

% Parachute (NED) relative velocities (plus wind) 
ur_para = u_para - uw;
vr_para = v_para - vw;
wr_para = w_para - ww;

Vels_para = [u_para v_para w_para];
V_norm_para = norm([ur_para vr_para wr_para]);

%% PARACHUTE REFERENCE FRAME
% The parachutes are approximated as rectangular surfaces with the normal
% vector perpendicular to the relative velocity

t_vect = -[ur_para vr_para wr_para];                                          % Tangenzial vector
h_vect = [vr_para -ur_para 0];                                                % horizontal vector    

if all(abs(h_vect) < 1e-8)
    if all([uw vw 0] == 0) % to prevent NaN
        t_vers = t_vect/norm(t_vect);                                         % Tangenzial versor
        h_vers = [0 0 0];                                                     % horizontal versor
        n_vers = [0 0 0];                                                     % Normal versor
    else
        h_vect = [vw -uw 0];
        t_vers = t_vect/norm(t_vect);
        h_vers = h_vect/norm(h_vect);
        n_vect = cross(t_vers, h_vers);
        n_vers = n_vect/norm(n_vect);
    end
else
    t_vers = t_vect/norm(t_vect);
    h_vers = h_vect/norm(h_vect);
    n_vect = cross(t_vers, h_vers);
    n_vers = n_vect/norm(n_vect);
end

if (n_vers(3) > 0) % If the normal vector is downward directed
    n_vect = cross(h_vers, t_vers);
    n_vers = n_vect/norm(n_vect);
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

%% RELATIVE POSITION AND VELOCITY VECTORS
% (NED) positions of parachute and rocket
pos_para = [x_para y_para z_para]; pos_rocket = [x_rocket y_rocket z_rocket];

% (NED) parachute velocity, (BODY) rocket velocity
vel_para = [u_para v_para w_para]; vel_rocket = [u_rocket v_rocket w_rocket];

% (NED) relative position vector pointed from xcg to the point from where the
% parachute has been deployed
posRelXcg_Poi = quatrotate(Q_conj_rocket,[(settings.xcg-settings.Lnose) 0 0]);

% (NED) position vector of that point from the origin
pos_Poi = pos_rocket + posRelXcg_Poi;

% (BODY) velocity vector of that point
vel_Poi = vel_rocket + cross([p_rocket q_rocket r_rocket],[(settings.xcg-settings.Lnose) 0 0]);

% Relative position vector between parachute and that point.
relPos_vecNED = pos_para - pos_Poi;                                           % (NED) relative position vector pointed towards parachute
relPos_vecBODY = quatrotate(Q_rocket,relPos_vecNED);                          % (BODY)   "         "      "       "       "       "
relPos_versNED = relPos_vecNED/norm(relPos_vecNED);                           % (NED) relative position versor pointed towards parachute
relPos_versBODY = relPos_vecBODY/norm(relPos_vecBODY);                        % (BODY)   "         "      "       "       "       "

if all(abs(relPos_vecNED) < 1e-8) || all(abs(relPos_vecBODY) < 1e-8)          % to prevent NaN
    relPos_vecNED = [0 0 0];
    relPos_versNED = [0 0 0];
    relPos_versBODY= [0 0 0];
end

% (NED) relative velocity vector between parachute and that point, pointed
% towards rocket
relVel_vecNED = quatrotate(Q_conj_rocket,vel_Poi) - vel_para;

% (NED) relative velocity projected along the chock chord. Pointed towards
% parachute
relVel_chord = relVel_vecNED * relPos_versNED';

%% CHORD TENSION (ELASTIC-DAMPING MODEL)
if norm(relPos_vecNED) > settings.para(para).L                      % [N] Chord tension (elastic-damping model)
    T_chord = (norm(relPos_vecNED) - settings.para(para).L)* settings.para(para).K -...
        relVel_chord * settings.para(para).C;
else
    T_chord = 0;
end

%% PARACHUTE FORCES
% computed in the NED-frame reference system
S_para = settings.para(para).S;                                                   % [m^2]   Surface
CD_para = settings.para(para).CD;
D0 = sqrt(4*settings.para(para).S/pi);
t0 = settings.para(para).nf * D0/V_norm_para;
tx = t0 * settings.para(para).CX^(1/settings.para(para).m);
SCD0 = S_para*CD_para;

dt = t-t0p;

if dt < 0
    SCD_para = 0;
elseif dt < tx
    SCD_para = SCD0 * (dt/t0)^settings.para(para).m;
else
    SCD_para = SCD0 * (1+(settings.para(para).CX-1)*exp(-2*(dt-tx)/t0));
end

D_para = 0.5*rho*V_norm_para^2*SCD_para*t_vers';
Fg_para = [0 0 m_para*g]';                                                    % [N] Gravitational Force vector

Ft_chord_para = -T_chord * relPos_versNED;                                    % [N] Chord tension vector (parachute view)
F_para = D_para + Fg_para + Ft_chord_para';                          % [N] (BODY) total forces vector

%% ROCKET FORCES
% computed in the body-frame reference system
Fg_rocket = quatrotate(Q_rocket,[0 0 m_rocket*g])';                           % [N] force due to the gravity

Ft_chord_rocket = T_chord * relPos_versBODY;                                  % [N] Chord tension vector (rocket view)
F_rocket = Fg_rocket + Ft_chord_rocket';                                      % [N] (NED) total forces vector

%% ROCKET STATE DERIVATIVES
% velocity (BODY frame)
du_rocket = F_rocket(1)/m_rocket-q_rocket*w_rocket+r_rocket*v_rocket;
dv_rocket = F_rocket(2)/m_rocket-r_rocket*u_rocket+p_rocket*w_rocket;
dw_rocket = F_rocket(3)/m_rocket-p_rocket*v_rocket+q_rocket*u_rocket;

% Rotation
b = [(settings.xcg-settings.Lnose) 0 0];
Momentum = cross(b, Ft_chord_rocket);                                          % [Nm] Chord tension moment

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
du_para = F_para(1)/m_para;
dv_para = F_para(2)/m_para;
dw_para = F_para(3)/m_para;

%% FINAL DERIVATIVE STATE ASSEMBLING
dY(1:3) = Vels_rocket;
dY(4) = du_rocket;
dY(5) = dv_rocket;
dY(6) = dw_rocket;
dY(7) = dp_rocket;
dY(8) = dq_rocket;
dY(9) = dr_rocket;
dY(10:13) = dQQ_rocket;
dY(14:16) = [p_rocket q_rocket r_rocket];
dY(17:19) = Vels_para;
dY(20) = du_para;
dY(21) = dv_para;
dY(22) = dw_para;
dY = dY';

%% SAVING THE QUANTITIES FOR THE PLOTS
parout.integration.t = t;

parout.interp.M = M_value_rocket;
parout.interp.alt = -z_rocket;

parout.wind.NED_wind = [uw, vw, ww];
parout.wind.body_wind = wind;

parout.velocities = Vels_rocket;

parout.air.rho = rho;
parout.air.P = P;

parout.accelerations.body_acc = [du_rocket, dv_rocket, dw_rocket];
parout.accelerations.ang_acc = [dp_rocket, dq_rocket, dr_rocket];

parout.forces.T_chord = [T_chord, NaN];
parout.forces.D = [norm(D_para), NaN];

parout.SCD = [SCD_para/SCD0, NaN];