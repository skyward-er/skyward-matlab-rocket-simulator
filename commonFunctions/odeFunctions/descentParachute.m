function [dY, parout] = descentParachute(t, Y, settings)
%{
descentParachute - ode function of the descent with parachute

INPUTS:
- t,         double [1, 1] integration time [s];
- Y,         double [6, 1] state vector [ x y z | u v w ]:
                                * (x y z), NED{north, east, down} horizontal frame;
                                * (u v w), body frame velocities;
- settings, struct(motor, CoeffsE, CoeffsF, para, ode, stoch, prob, wind), rocket data structure;

OUTPUTS:
- dY,        double[6, 1] state derivatives
- parout,    struct, interesting fligth quantities structure (aerodyn coefficients, forces and so on..)


CALLED FUNCTIONS: windMatlabGenerator, windInputGenerator


REVISIONS:
-#0 31/12/2014, Release, Ruben Di Battista

-#1 16/04/2016, Second version, Francesco Colombi

-#2 13/01/2018, Third version, Adriano Filippo Inno

%}

% recalling the state
% x = Y(1);
% y = Y(2);
z = Y(3);
u = Y(4);
v = Y(5);
w = Y(6);

%% CONSTANTS
if settings.stoch.N > 1
    uncert = settings.stoch.uncert;
    Day = settings.stoch.Day;
    Hour = settings.stoch.Hour;
    uw = settings.stoch.uw; vw = settings.stoch.vw; ww = settings.stoch.ww;
    para = settings.stoch.para;
else        
    uncert = settings.wind.inputUncertainty;
    uw = settings.constWind(1); vw = settings.constWind(2); ww = settings.constWind(3);
    para = settings.paraNumber;
end

S = settings.para(para).S;                                               % [m^2]   Surface
CD = settings.para(para).CD;                                             % [/] Parachute Drag Coefficient
CL = settings.para(para).CL;                                             % [/] Parachute Lift Coefficient
if para == 1
    pmass = 0 ;                                                          % [kg] detached mass
else
    pmass = sum(settings.para(1:para-1).mass) + settings.mnc;
end

g = 9.80655;                                                             % [N/kg] magnitude of the gravitational field at zero
m = settings.ms - pmass;                                                 % [kg] descend mass

%% ADDING WIND (supposed to be added in NED axes);
if settings.wind.model
    
    if settings.stoch.N > 1
        [uw, vw, ww] = windMatlabGenerator(settings, z, t, Hour, Day);
    else
        [uw, vw, ww] = windMatlabGenerator(settings, z, t);
    end
    
elseif settings.wind.input
    [uw, vw, ww] = windInputGenerator(settings, z, uncert);
end

wind = [uw vw ww];

% Relative velocities (plus wind);
ur = u - wind(1);
vr = v - wind(2);
wr = w - wind(3);

V_norm = norm([ur vr wr]);

%% ATMOSPHERE DATA
if -z < 0        % z is directed as the gravity vector
    z = 0;
end

absoluteAltitude = -z + settings.z0;
[~, ~, P, rho] = atmosphereData(absoluteAltitude, g);

%% REFERENCE FRAME
% The parachutes are approximated as rectangular surfaces with the normal
% vector perpendicular to the relative velocity
t_vect = [ur vr wr];                     % Tangenzial vector
h_vect = [-vr ur 0];                     % horizontal vector    

if all(abs(h_vect) < 1e-8)
    h_vect = [-vw uw 0];
end

t_vers = t_vect/norm(t_vect);            % Tangenzial versor
h_vers = -h_vect/norm(h_vect);           % horizontal versor

n_vect = cross(t_vers, h_vers);          % Normal vector
n_vers = n_vect/norm(n_vect);            % Normal versor

if (n_vers(3) > 0)                       % If the normal vector is downward directed
    n_vect = cross(h_vers, t_vers);
    n_vers = n_vect/norm(n_vect);
end

%% FORCES
D = 0.5*rho*V_norm^2*S*CD*t_vers';       % [N] Drag vector
L = 0.5*rho*V_norm^2*S*CL*n_vers';       % [N] Lift vector
Fg = m*g*[0 0 1]';                       % [N] Gravitational Force vector
F = L + Fg - D;                          % [N] total forces vector

%% STATE DERIVATIVES
% velocity
du = F(1)/m;
dv = F(2)/m;
dw = F(3)/m;

%% FINAL DERIVATIVE STATE ASSEMBLING
dY(1:3) = [u v w]';
dY(4) = du;
dY(5) = dv;
dY(6) = dw;

dY = dY';

%% SAVING THE QUANTITIES FOR THE PLOTS
%if settings.plots
    
    parout.integration.t = t;
    parout.interp.alt = -z;
    parout.wind.body_wind = [uw, vw, ww];
    parout.wind.NED_wind = [uw, vw, ww];
    
    parout.air.rho = rho;
    parout.air.P = P;
    
    parout.accelerations.body_acc = [du, dv, dw];
    
    parout.velocities = [u, v, w];
    
%end
