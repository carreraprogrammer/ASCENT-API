class Api::V1::RolesController < Api::V1::BaseController
  skip_after_action :verify_policy_scoped, only: :index

  def index
    authorize ::Role, policy_class: Authorization::Policies::RolePolicy
    roles = Authorization::Interactors::FetchAllRoles.new.call
    render json: Authorization::Presenters::RolePresenter.collection(roles)
  end

  def show
    role = Authorization::Interactors::FetchRole.new.call(id: params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    render json: Authorization::Presenters::RolePresenter.single(role)
  end

  def create
    authorize ::Role, policy_class: Authorization::Policies::RolePolicy
    role = Authorization::Interactors::CreateRole.new.call(name: params.require(:name), slug: params.require(:slug), description: params[:description])
    render json: Authorization::Presenters::RolePresenter.single(role), status: :created
  end

  def update
    role = Authorization::Interactors::FetchRole.new.call(id: params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    entity = Authorization::Interactors::UpdateRole.new.call(id: params[:id], attrs: params.permit(:name, :slug, :description, :active).to_h.symbolize_keys)
    render json: Authorization::Presenters::RolePresenter.single(entity)
  end

  def destroy
    role = Authorization::Interactors::FetchRole.new.call(id: params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    Authorization::Interactors::DestroyRole.new.call(id: params[:id])
    head :no_content
  end

  def assign_permission
    role = Authorization::Interactors::FetchRole.new.call(id: params[:id])
    authorize role, :assign_permission?, policy_class: Authorization::Policies::RolePolicy
    updated_role = Authorization::Interactors::AssignPermissionToRole.new.call(role_id: role.id, permission_slug: params.require(:permission_slug))
    render json: Authorization::Presenters::RolePresenter.single(updated_role)
  end

  def revoke_permission
    role = Authorization::Interactors::FetchRole.new.call(id: params[:id])
    authorize role, :revoke_permission?, policy_class: Authorization::Policies::RolePolicy
    Authorization::Interactors::RevokePermissionFromRole.new.call(role_id: role.id, permission_slug: params.require(:permission_slug))
    head :no_content
  end
end
